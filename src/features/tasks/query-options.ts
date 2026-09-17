import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";

import type { TaskFilter } from "@/contracts/tasks";
import { queryKeys } from "@/lib/query/keys";

import {
  TASK_PAGE_SIZE,
  getTask,
  listLeadingTasks,
  listMyTasks,
  listTasksByProject,
  listTaskAttachments,
  listTaskSubmissions
} from "./api/tasks-api";
import type { TaskFeedPage } from "./feed";
import { sortTasksByDeadline } from "./selectors";

export type { TaskFeedPage } from "./feed";

export function myTasksQueryOptions(userId: string, filter: TaskFilter, page: number) {
  return queryOptions({
    queryKey: queryKeys.tasks.list(userId, filter, page),
    queryFn: async ({ signal }) => {
      const tasks = await listMyTasks(userId, { page, filter, signal });
      return sortTasksByDeadline(tasks);
    },
    staleTime: 30_000
  });
}

export function myTasksInfiniteQueryOptions(userId: string, filter: TaskFilter) {
  return infiniteQueryOptions({
    queryKey: queryKeys.tasks.feed(userId, filter),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<TaskFeedPage> => {
      const tasks = await listMyTasks(userId, { page: pageParam, filter, signal });
      return {
        items: sortTasksByDeadline(tasks),
        nextPage: tasks.length === TASK_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function leadingTasksQueryOptions(userId: string, filter: TaskFilter, page: number) {
  return queryOptions({
    queryKey: queryKeys.tasks.leading(userId, filter, page),
    queryFn: async ({ signal }) => {
      const tasks = await listLeadingTasks(userId, { page, filter, signal });
      return sortTasksByDeadline(tasks);
    },
    staleTime: 30_000
  });
}

export function leadingTasksInfiniteQueryOptions(userId: string, filter: TaskFilter) {
  return infiniteQueryOptions({
    queryKey: queryKeys.tasks.leadingFeed(userId, filter),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<TaskFeedPage> => {
      const tasks = await listLeadingTasks(userId, { page: pageParam, filter, signal });
      return {
        items: sortTasksByDeadline(tasks),
        nextPage: tasks.length === TASK_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function projectTasksInfiniteQueryOptions(projectId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.tasks.byProject(projectId),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<TaskFeedPage> => {
      const tasks = await listTasksByProject(projectId, { page: pageParam, signal });
      return {
        items: sortTasksByDeadline(tasks),
        nextPage: tasks.length === TASK_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function taskDetailQueryOptions(taskId: string) {
  return queryOptions({
    queryKey: queryKeys.tasks.detail(taskId),
    queryFn: ({ signal }) => getTask(taskId, signal),
    staleTime: 15_000
  });
}

export function taskSubmissionsQueryOptions(taskId: string, page: number) {
  return queryOptions({
    queryKey: queryKeys.tasks.submissions(taskId, page),
    queryFn: ({ signal }) => listTaskSubmissions(taskId, { page, signal }),
    staleTime: 15_000
  });
}

/** Attachment reads are always bound to one immutable submission attempt. */
export function taskAttachmentsQueryOptions(taskId: string, submissionId: string) {
  return queryOptions({
    queryKey: queryKeys.tasks.attachments(taskId, submissionId),
    queryFn: ({ signal }) => listTaskAttachments(taskId, submissionId, signal),
    staleTime: 15_000
  });
}
