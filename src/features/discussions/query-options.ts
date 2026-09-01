import { infiniteQueryOptions } from "@tanstack/react-query";

import { queryKeys } from "@/lib/query/keys";

import { TASK_COMMENT_PAGE_SIZE, listTaskComments } from "./api/discussions-api";

export function taskCommentsInfiniteQueryOptions(taskId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.discussions.task(taskId, 0),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }) => {
      const items = await listTaskComments(taskId, pageParam, signal);
      return { items, nextPage: items.length === TASK_COMMENT_PAGE_SIZE ? pageParam + 1 : null };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 15_000
  });
}
