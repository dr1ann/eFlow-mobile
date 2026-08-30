import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import type { Notification, NotificationDestination, NotificationKind } from "@/contracts/notifications";

const nullableText = z.string().nullable();
const nullableUuid = z.string().uuid().nullable();

const notificationRowSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  type: z.string(),
  title: z.string().trim().min(1),
  message: z.string(),
  read: z.boolean().nullable(),
  created_at: nullableText,
  task_id: nullableUuid,
  project_id: nullableUuid,
  actor_id: nullableUuid,
  actor_name: nullableText,
  reason: nullableText
});

function notificationKind(value: string): NotificationKind {
  if (value === "approval_needed" || value === "completed" || value === "status_change") return value;
  return "unknown";
}

function destination(taskId: string | null, projectId: string | null): NotificationDestination {
  if (taskId) return { kind: "task", taskId };
  if (projectId) return { kind: "project", projectId };
  return { kind: "none" };
}

export function mapNotificationRow(row: unknown): Notification {
  const parsed = notificationRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("notification");

  const data = parsed.data;
  const kind = notificationKind(data.type);
  const isSupportedOnMobile = kind !== "unknown";

  // New notification types can include finance or other workflows that are not
  // available on mobile. Keep them visible as a generic inbox event without
  // exposing their title, message, actor, reason, or a destination.
  if (!isSupportedOnMobile) {
    return {
      id: data.id,
      userId: data.user_id,
      kind,
      title: "Notification unavailable on mobile",
      message: "This notification belongs to a workflow that is not yet available in the mobile app.",
      isRead: data.read ?? false,
      createdAt: data.created_at,
      taskId: null,
      projectId: null,
      actorId: null,
      actorName: null,
      reason: null,
      destination: { kind: "none" }
    };
  }

  return {
    id: data.id,
    userId: data.user_id,
    kind,
    title: data.title,
    message: data.message,
    isRead: data.read ?? false,
    createdAt: data.created_at,
    taskId: data.task_id,
    projectId: data.project_id,
    actorId: data.actor_id,
    actorName: data.actor_name,
    reason: data.reason,
    destination: destination(data.task_id, data.project_id)
  };
}
