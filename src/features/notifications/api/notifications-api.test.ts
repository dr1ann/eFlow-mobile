import {
  NOTIFICATION_PAGE_SIZE,
  NOTIFICATION_SELECT,
  getNotificationForRecipient,
  listNotifications,
  notificationPageRange
} from "@/features/notifications/api/notifications-api";
import { SupabaseUserError } from "@/lib/supabase/errors";

const mockFrom = jest.fn();

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({ from: mockFrom })
}));

const ids = {
  notification: "11111111-1111-4111-8111-111111111111",
  user: "22222222-2222-4222-8222-222222222222",
  task: "33333333-3333-4333-8333-333333333333"
};

const notificationRow = {
  id: ids.notification,
  user_id: ids.user,
  type: "approval_needed",
  title: "Review needed",
  message: "A task is ready.",
  read: false,
  created_at: "2026-08-30T00:00:00+00:00",
  task_id: ids.task,
  project_id: null,
  actor_id: null,
  actor_name: null,
  reason: null
};

function createQuery(result: unknown) {
  const query = {
    select: jest.fn(),
    eq: jest.fn(),
    order: jest.fn(),
    range: jest.fn(),
    abortSignal: jest.fn(),
    maybeSingle: jest.fn()
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.range.mockResolvedValue(result);
  query.abortSignal.mockReturnValue(query);
  query.maybeSingle.mockResolvedValue(result);
  return query;
}

describe("notification read API", () => {
  beforeEach(() => jest.clearAllMocks());

  it("uses a minimal, paged query scoped to the active notification recipient", async () => {
    const query = createQuery({ data: [notificationRow], error: null });
    mockFrom.mockReturnValue(query);

    await expect(listNotifications(ids.user, { page: 1 })).resolves.toMatchObject([
      { id: ids.notification, userId: ids.user, destination: { kind: "task", taskId: ids.task } }
    ]);

    expect(mockFrom).toHaveBeenCalledWith("notifications");
    expect(query.select).toHaveBeenCalledWith(NOTIFICATION_SELECT);
    expect(NOTIFICATION_SELECT).not.toContain("financial_record");
    expect(query.eq).toHaveBeenCalledWith("user_id", ids.user);
    expect(query.order).toHaveBeenNthCalledWith(1, "created_at", {
      ascending: false,
      nullsFirst: false
    });
    expect(query.range).toHaveBeenCalledWith(NOTIFICATION_PAGE_SIZE, NOTIFICATION_PAGE_SIZE * 2 - 1);
  });

  it("keeps a missing or RLS-hidden canonical notification unavailable", async () => {
    const query = createQuery({ data: null, error: null });
    mockFrom.mockReturnValue(query);

    await expect(getNotificationForRecipient(ids.notification, ids.user)).resolves.toBeNull();
    expect(query.eq).toHaveBeenNthCalledWith(1, "id", ids.notification);
    expect(query.eq).toHaveBeenNthCalledWith(2, "user_id", ids.user);
  });

  it("passes cancellation through the recipient-scoped detail read", async () => {
    const query = createQuery({ data: notificationRow, error: null });
    mockFrom.mockReturnValue(query);
    const controller = new AbortController();

    await expect(
      getNotificationForRecipient(ids.notification, ids.user, controller.signal)
    ).resolves.toMatchObject({ id: ids.notification });
    expect(query.abortSignal).toHaveBeenCalledWith(controller.signal);
  });

  it("maps Supabase errors without exposing policy details", async () => {
    const query = createQuery({
      data: null,
      error: { code: "42501", message: "recipient policy internals" }
    });
    mockFrom.mockReturnValue(query);

    await expect(listNotifications(ids.user, { page: 0 })).rejects.toEqual(
      new SupabaseUserError("forbidden", "You do not have access to complete this action.")
    );
  });

  it("normalizes negative page inputs", () => {
    expect(notificationPageRange(-2)).toEqual([0, NOTIFICATION_PAGE_SIZE - 1]);
  });
});
