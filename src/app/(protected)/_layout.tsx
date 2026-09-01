import { Stack } from "expo-router/stack";

import { canOpenPermissionRoute } from "@/features/auth/access-policy";
import { useAuth } from "@/features/auth/auth-context";

export default function ProtectedLayout() {
  const { state } = useAuth();

  return (
    <Stack>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="settings" options={{ title: "Settings" }} />
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.user_management")}>
        <Stack.Screen name="access-check" options={{ title: "Access check" }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.tasks")}>
        <Stack.Screen name="tasks/[task-id]" options={{ title: "Task details" }} />
        <Stack.Screen name="tasks/[task-id]/submit" options={{ title: "Submit task" }} />
        <Stack.Screen name="tasks/[task-id]/discussion" options={{ title: "Task discussion" }} />
        <Stack.Screen name="subtasks/[subtask-id]" options={{ title: "Subtask details" }} />
        <Stack.Screen name="subtasks/[subtask-id]/progress" options={{ title: "Update progress" }} />
        <Stack.Screen name="subtasks/[subtask-id]/submit" options={{ title: "Submit subtask" }} />
        <Stack.Screen name="reviews/index" options={{ title: "Review inbox" }} />
        <Stack.Screen name="reviews/subtasks/[subtask-id]" options={{ title: "Review subtask" }} />
        <Stack.Screen name="reviews/tasks/[task-id]" options={{ title: "Review task" }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.projects")}>
        <Stack.Screen name="projects/[project-id]" options={{ title: "Project details" }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.announcements")}>
        <Stack.Screen name="announcements" options={{ title: "Notices" }} />
      </Stack.Protected>
    </Stack>
  );
}
