import { fireEvent, render } from "@testing-library/react-native";

import type { Notification } from "@/contracts/notifications";
import {
  NotificationListScreenView,
  flattenNotificationFeed
} from "@/features/notifications/screens/notification-list-screen";

const notification = {
  id: "11111111-1111-4111-8111-111111111111",
  userId: "22222222-2222-4222-8222-222222222222",
  kind: "approval_needed",
  title: "Review needed",
  message: "A task is ready.",
  isRead: false,
  createdAt: "2026-08-30T00:00:00+00:00",
  taskId: "33333333-3333-4333-8333-333333333333",
  projectId: null,
  actorId: null,
  actorName: null,
  reason: null,
  destination: { kind: "task", taskId: "33333333-3333-4333-8333-333333333333" }
} satisfies Notification;

const baseProps = {
  isLoading: false,
  isRefreshing: false,
  isError: false,
  isPaused: false,
  hasNextPage: false,
  isFetchingNextPage: false,
  canOpenNotification: jest.fn(() => true),
  canMarkRead: false,
  markingNotificationId: null,
  onRefresh: jest.fn(),
  onLoadMore: jest.fn(),
  onOpenNotification: jest.fn(),
  onMarkRead: jest.fn()
};

describe("NotificationListScreenView", () => {
  beforeEach(() => jest.clearAllMocks());

  it("renders a recipient notification and opens its guarded destination accessibly", async () => {
    const onOpenNotification = jest.fn();
    const view = await render(
      <NotificationListScreenView
        {...baseProps}
        notifications={[notification]}
        onOpenNotification={onOpenNotification}
      />
    );

    expect(view.getByText("Review needed")).toBeTruthy();
    expect(view.getByText("Unread")).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open linked item/));
    expect(onOpenNotification).toHaveBeenCalledWith(notification);
  });

  it("shows unavailable destinations without making them actionable", async () => {
    const unavailable = { ...notification, destination: { kind: "none" as const } };
    const view = await render(
      <NotificationListScreenView
        {...baseProps}
        notifications={[unavailable]}
        canOpenNotification={() => false}
      />
    );

    expect(view.getByLabelText(/No supported destination/).props.accessibilityState).toEqual({
      disabled: true
    });
  });

  it("shows empty, retry, and offline cached states", async () => {
    const onRefresh = jest.fn();
    const empty = await render(
      <NotificationListScreenView {...baseProps} notifications={[]} onRefresh={onRefresh} isPaused />
    );
    expect(empty.getByText("No notifications are available.")).toBeTruthy();
    expect(empty.getByText(/Showing cached notifications/i)).toBeTruthy();
    await empty.unmount();

    const failed = await render(
      <NotificationListScreenView
        {...baseProps}
        notifications={[]}
        onRefresh={onRefresh}
        isError
      />
    );
    expect(failed.getByText(/could not load notifications/i)).toBeTruthy();
    await fireEvent.press(failed.getByLabelText("Try again"));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it("shows loading and exposes pagination through accessible controls", async () => {
    const onLoadMore = jest.fn();
    const loading = await render(
      <NotificationListScreenView {...baseProps} notifications={[]} isLoading />
    );
    expect(loading.getByLabelText("Loading notifications")).toBeTruthy();
    await loading.unmount();

    const paged = await render(
      <NotificationListScreenView
        {...baseProps}
        notifications={[notification]}
        hasNextPage
        onLoadMore={onLoadMore}
      />
    );
    await fireEvent.press(paged.getByLabelText("Load more notifications"));
    expect(onLoadMore).toHaveBeenCalledTimes(1);
  });

  it("deduplicates rows received again after pagination or refresh", () => {
    expect(
      flattenNotificationFeed([
        { items: [notification], nextPage: 1 },
        { items: [{ ...notification, isRead: true }], nextPage: null }
      ])
    ).toEqual([{ ...notification, isRead: true }]);
  });
});
