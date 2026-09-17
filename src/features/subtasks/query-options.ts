import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";

import type { Subtask, SubtaskFilter } from "@/contracts/subtasks";
import { queryKeys } from "@/lib/query/keys";

import {
  getSubtask,
  listMySubtasks,
  listSubtaskProgress,
  listSubtaskSubmissionAttachments,
  listSubtaskSubmissions,
  listSubtasksByTask
} from "./api/subtasks-api";
import { sortSubtasksByDeadline } from "./selectors";

export interface SubtaskFeedPage {
  items: readonly Subtask[];
  nextPage: number | null;
}

export function mySubtasksQueryOptions(userId: string, filter: SubtaskFilter, page: number) {
  return queryOptions({
    queryKey: queryKeys.subtasks.mine(userId, filter, page),
    queryFn: async ({ signal }) => {
      const subtasks = await listMySubtasks(userId, { page, filter, signal });
      return sortSubtasksByDeadline(subtasks);
    },
    staleTime: 30_000
  });
}

export function mySubtasksInfiniteQueryOptions(userId: string, filter: SubtaskFilter) {
  return infiniteQueryOptions({
    queryKey: queryKeys.subtasks.feed(userId, filter),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<SubtaskFeedPage> => {
      const subtasks = await listMySubtasks(userId, { page: pageParam, filter, signal });
      return {
        items: sortSubtasksByDeadline(subtasks),
        nextPage: subtasks.length === 30 ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function subtasksByTaskQueryOptions(taskId: string) {
  return queryOptions({
    queryKey: queryKeys.subtasks.byTask(taskId),
    queryFn: ({ signal }) => listSubtasksByTask(taskId, signal),
    staleTime: 15_000
  });
}

export function subtaskDetailQueryOptions(subtaskId: string) {
  return queryOptions({
    queryKey: queryKeys.subtasks.detail(subtaskId),
    queryFn: ({ signal }) => getSubtask(subtaskId, signal),
    staleTime: 15_000
  });
}

export function subtaskProgressQueryOptions(subtaskId: string, page: number) {
  return queryOptions({
    queryKey: queryKeys.subtasks.progress(subtaskId, page),
    queryFn: ({ signal }) => listSubtaskProgress(subtaskId, { page, signal }),
    staleTime: 15_000
  });
}

export function subtaskSubmissionsQueryOptions(subtaskId: string, page: number) {
  return queryOptions({
    queryKey: queryKeys.subtasks.submissions(subtaskId, page),
    queryFn: ({ signal }) => listSubtaskSubmissions(subtaskId, { page, signal }),
    staleTime: 15_000
  });
}

export function subtaskSubmissionAttachmentsQueryOptions(submissionId: string) {
  return queryOptions({
    queryKey: ["subtasks", "submission-attachments", submissionId] as const,
    queryFn: ({ signal }) => listSubtaskSubmissionAttachments(submissionId, signal),
    staleTime: 15_000
  });
}
