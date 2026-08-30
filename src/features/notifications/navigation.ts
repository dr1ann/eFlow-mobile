import type { Href } from "expo-router";

import type { Notification } from "@/contracts/notifications";
import type { PermissionKey } from "@/contracts/permissions";
import { parseUuidParam } from "@/lib/navigation/params";

export interface NotificationNavigationTarget {
  requiredPermission: Extract<PermissionKey, "navigation.tasks" | "navigation.projects">;
  href: Href;
}

/**
 * Routes only the small destination allowlist backed by existing guarded detail
 * screens. The destination record is fetched again under RLS after navigation.
 */
export function notificationNavigationTarget(
  notification: Notification
): NotificationNavigationTarget | null {
  if (notification.destination.kind === "task") {
    const taskId = parseUuidParam(notification.destination.taskId);
    if (!taskId) return null;
    return {
      requiredPermission: "navigation.tasks",
      href: { pathname: "/tasks/[task-id]", params: { "task-id": taskId } }
    };
  }

  if (notification.destination.kind === "project") {
    const projectId = parseUuidParam(notification.destination.projectId);
    if (!projectId) return null;
    return {
      requiredPermission: "navigation.projects",
      href: { pathname: "/projects/[project-id]", params: { "project-id": projectId } }
    };
  }

  return null;
}

export function canOpenNotificationDestination(
  notification: Notification,
  can: (permission: PermissionKey) => boolean
): boolean {
  const target = notificationNavigationTarget(notification);
  return target !== null && can(target.requiredPermission);
}
