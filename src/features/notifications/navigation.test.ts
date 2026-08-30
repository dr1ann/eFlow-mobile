import { ContractMappingError } from "@/contracts/contract-errors";
import { mapNotificationRow } from "@/features/notifications/mappers";

const ids = {
  notification: "11111111-1111-4111-8111-111111111111",
  user: "22222222-2222-4222-8222-222222222222",
  task: "33333333-3333-4333-8333-333333333333",
  project: "44444444-4444-4444-8444-444444444444"
};

function row(overrides: Record<string, unknown> = {}): unknown {
  return {
    id: ids.notification,
    user_id: ids.user,
    type: "approval_needed",
    title: "Review needed",
    message: "A task is ready.",
    read: false,
    created_at: "2026-08-26T00:00:00+00:00",
    task_id: ids.task,
    project_id: ids.project,
    actor_id: null,
    actor_name: null,
    reason: null,
    ...overrides
  };
}

describe("notification navigation mapper", () => {
  it("prefers the task destination and preserves a safe known kind", () => {
    expect(mapNotificationRow(row())).toMatchObject({
      kind: "approval_needed",
      destination: { kind: "task", taskId: ids.task }
    });
  });

  it("keeps unknown notification types visible without exposing unsupported workflow details", () => {
    expect(
      mapNotificationRow(
        row({
          type: "financial_approval",
          title: "Cash request requires action",
          message: "A private financial message",
          task_id: null,
          project_id: null
        })
      )
    ).toMatchObject({
      kind: "unknown",
      title: "Notification unavailable on mobile",
      message: "This notification belongs to a workflow that is not yet available in the mobile app.",
      destination: { kind: "none" },
      actorId: null,
      reason: null
    });
  });

  it("fails closed when the recipient scope is malformed", () => {
    expect(() => mapNotificationRow(row({ user_id: "not-a-uuid" }))).toThrow(ContractMappingError);
  });
});
