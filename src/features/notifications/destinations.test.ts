import type { Notification } from "@/contracts/notifications";
import {
  canOpenNotificationDestination,
  notificationNavigationTarget
} from "@/features/notifications/navigation";

const ids = {
  notification: "11111111-1111-4111-8111-111111111111",
  user: "22222222-2222-4222-8222-222222222222",
  task: "33333333-3333-4333-8333-333333333333",
  project: "44444444-4444-4444-8444-444444444444"
};

function notification(destination: Notification["destination"]): Notification {
  return {
    id: ids.notification,
    userId: ids.user,
    kind: "approval_needed",
    title: "Review needed",
    message: "A task is ready.",
    isRead: false,
    createdAt: null,
    taskId: destination.kind === "task" ? destination.taskId : null,
    projectId: destination.kind === "project" ? destination.projectId : null,
    actorId: null,
    actorName: null,
    reason: null,
    destination
  };
}

describe("notification destination navigation", () => {
  it("maps only allowlisted task and project destinations to guarded routes", () => {
    expect(notificationNavigationTarget(notification({ kind: "task", taskId: ids.task }))).toEqual({
      requiredPermission: "navigation.tasks",
      href: { pathname: "/tasks/[task-id]", params: { "task-id": ids.task } }
    });
    expect(notificationNavigationTarget(notification({ kind: "project", projectId: ids.project }))).toEqual({
      requiredPermission: "navigation.projects",
      href: { pathname: "/projects/[project-id]", params: { "project-id": ids.project } }
    });
  });

  it("fails closed for missing or malformed destinations", () => {
    expect(notificationNavigationTarget(notification({ kind: "none" }))).toBeNull();
    expect(
      notificationNavigationTarget(notification({ kind: "task", taskId: "not-a-uuid" }))
    ).toBeNull();
  });

  it("requires the current matching navigation permission before opening", () => {
    const taskNotification = notification({ kind: "task", taskId: ids.task });
    expect(canOpenNotificationDestination(taskNotification, () => false)).toBe(false);
    expect(canOpenNotificationDestination(taskNotification, (permission) => permission === "navigation.tasks")).toBe(true);
  });
});
