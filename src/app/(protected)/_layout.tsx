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
    </Stack>
  );
}
