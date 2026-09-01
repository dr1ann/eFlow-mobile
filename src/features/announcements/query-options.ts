import { infiniteQueryOptions } from "@tanstack/react-query";

import { queryKeys } from "@/lib/query/keys";

import { ANNOUNCEMENT_PAGE_SIZE, listRecipientAnnouncements } from "./api/announcements-api";

export function announcementsInfiniteQueryOptions(userId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.announcements.list(userId, "published", 0),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }) => {
      const items = await listRecipientAnnouncements(userId, pageParam, signal);
      return { items, nextPage: items.length === ANNOUNCEMENT_PAGE_SIZE ? pageParam + 1 : null };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}
