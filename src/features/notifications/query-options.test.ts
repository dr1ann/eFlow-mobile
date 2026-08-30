import {
  notificationDetailQueryOptions,
  notificationsInfiniteQueryOptions
} from "@/features/notifications/query-options";
import { queryKeys } from "@/lib/query/keys";

const ids = {
  user: "22222222-2222-4222-8222-222222222222",
  notification: "11111111-1111-4111-8111-111111111111"
};

describe("notification query options", () => {
  it("scopes the feed and canonical detail read to the signed-in recipient", () => {
    expect(notificationsInfiniteQueryOptions(ids.user).queryKey).toEqual(
      queryKeys.notifications.feed(ids.user)
    );
    expect(notificationDetailQueryOptions(ids.user, ids.notification).queryKey).toEqual(
      queryKeys.notifications.detail(ids.user, ids.notification)
    );
  });
});
