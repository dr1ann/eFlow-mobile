import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";

import type { Notification } from "@/contracts/notifications";
import { queryKeys } from "@/lib/query/keys";

import {
  NOTIFICATION_PAGE_SIZE,
  getNotificationForRecipient,
  listNotifications
} from "./api/notifications-api";

export interface NotificationFeedPage {
  items: readonly Notification[];
  nextPage: number | null;
}

export function notificationsInfiniteQueryOptions(userId: string) {
  return infiniteQueryOptions({
    queryKey: queryKeys.notifications.feed(userId),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<NotificationFeedPage> => {
      const notifications = await listNotifications(userId, { page: pageParam, signal });
      return {
        items: notifications,
        nextPage: notifications.length === NOTIFICATION_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function notificationDetailQueryOptions(userId: string, notificationId: string) {
  return queryOptions({
    queryKey: queryKeys.notifications.detail(userId, notificationId),
    queryFn: ({ signal }) => getNotificationForRecipient(notificationId, userId, signal),
    staleTime: 15_000
  });
}
