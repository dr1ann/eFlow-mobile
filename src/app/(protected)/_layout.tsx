import { Stack } from "expo-router/stack";

import { canOpenPermissionRoute } from "@/features/auth/access-policy";
import { useAuth } from "@/features/auth/auth-context";

export default function ProtectedLayout() {
  const { state } = useAuth();

  return (
    <Stack>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.user_management")}>
        <Stack.Screen name="access-check" options={{ title: "Access check" }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.tasks")}>
        <Stack.Screen name="tasks/[task-id]" options={{ title: "Task details" }} />
        <Stack.Screen name="subtasks/[subtask-id]" options={{ title: "Subtask details" }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenPermissionRoute(state, "navigation.projects")}>
        <Stack.Screen name="projects/[project-id]" options={{ title: "Project details" }} />
      </Stack.Protected>
    </Stack>
  );
}
