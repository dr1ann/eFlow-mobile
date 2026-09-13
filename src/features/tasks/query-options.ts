import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";

import type { Task, TaskFilter } from "@/contracts/tasks";
import { queryKeys } from "@/lib/query/keys";

import {
  TASK_PAGE_SIZE,
  getTask,
  listLeadingTasks,
  listMyTasks,
  listTaskAttachments,
  listTaskSubmissions
} from "./api/tasks-api";
import { sortTasksByDeadline, taskMatchesFilter } from "./selectors";

export interface TaskFeedPage {
  items: readonly Task[];
  nextPage: number | null;
}

export function myTasksQueryOptions(userId: string, filter: TaskFilter, page: number) {
  return queryOptions({
    queryKey: queryKeys.tasks.list(userId, filter, page),
    queryFn: async ({ signal }) => {
      const tasks = await listMyTasks(userId, { page, signal });
      return sortTasksByDeadline(tasks.filter((task) => taskMatchesFilter(task, filter, tasks)));
    },
    staleTime: 30_000
  });
}

export function myTasksInfiniteQueryOptions(userId: string, filter: TaskFilter) {
  return infiniteQueryOptions({
    queryKey: queryKeys.tasks.feed(userId, filter),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<TaskFeedPage> => {
      const tasks = await listMyTasks(userId, { page: pageParam, signal });
      return {
        items: sortTasksByDeadline(
          tasks.filter((task) => taskMatchesFilter(task, filter, tasks))
        ),
        nextPage: tasks.length === TASK_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function leadingTasksQueryOptions(userId: string, page: number) {
  return queryOptions({
    queryKey: queryKeys.tasks.leading(userId, page),
    queryFn: ({ signal }) => listLeadingTasks(userId, { page, signal }),
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
