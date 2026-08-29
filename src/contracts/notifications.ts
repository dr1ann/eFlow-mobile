export type NotificationKind =
  | "approval_needed"
  | "completed"
  | "status_change"
  | "unknown";

export type NotificationDestination =
  | { kind: "task"; taskId: string }
  | { kind: "project"; projectId: string }
  | { kind: "none" };

export interface Notification {
  id: string;
  userId: string;
  kind: NotificationKind;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string | null;
  taskId: string | null;
  projectId: string | null;
  actorId: string | null;
  actorName: string | null;
  reason: string | null;
  destination: NotificationDestination;
}
