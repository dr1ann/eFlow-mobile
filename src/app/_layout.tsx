import { Stack } from "expo-router/stack";

import { useAuth } from "@/features/auth/auth-context";
import { canOpenAuthenticatedRoute } from "@/features/auth/access-policy";
import { BootScreen } from "@/features/shell/screens/boot-screen";
import { AppProviders } from "@/providers/app-providers";
import { colors } from "@/theme/colors";

function RootNavigator() {
  const { state } = useAuth();

  if (state.kind === "booting" || state.kind === "loadingAccess") return <BootScreen />;

  return (
    <Stack screenOptions={{ headerBackButtonDisplayMode: "minimal", contentStyle: { backgroundColor: colors.background } }}>
      <Stack.Protected guard={state.kind === "signedOut"}>
        <Stack.Screen name="(auth)" options={{ headerShown: false }} />
      </Stack.Protected>
      <Stack.Protected guard={state.kind === "configuration" || state.kind === "rejected"}>
        <Stack.Screen name="(rejected)" options={{ headerShown: false }} />
      </Stack.Protected>
      <Stack.Protected guard={canOpenAuthenticatedRoute(state)}>
        <Stack.Screen name="(protected)" options={{ headerShown: false }} />
      </Stack.Protected>
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <AppProviders>
      <RootNavigator />
    </AppProviders>
  );
}
