import { infiniteQueryOptions } from "@tanstack/react-query";

import { queryKeys } from "@/lib/query/keys";

import { listPendingSubtaskReviews, listPendingTaskReviews, REVIEW_PAGE_SIZE } from "./api/reviews-api";

export function pendingTaskReviewsQueryOptions(userId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.reviews.inbox(userId, "task", 0),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }) => {
      const items = await listPendingTaskReviews(userId, pageParam, signal);
      return { items, nextPage: items.length === REVIEW_PAGE_SIZE ? pageParam + 1 : null };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 15_000
  });
}

export function pendingSubtaskReviewsQueryOptions(userId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.reviews.inbox(userId, "subtask", 0),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }) => {
      const items = await listPendingSubtaskReviews(userId, pageParam, signal);
      return { items, nextPage: items.length === REVIEW_PAGE_SIZE ? pageParam + 1 : null };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 15_000
  });
}
