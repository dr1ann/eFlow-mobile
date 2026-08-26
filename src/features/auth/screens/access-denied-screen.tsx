import { Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function AccessDeniedScreen() {
  const { state, retryAccess, signOut } = useAuth();
  const message = state.kind === "configuration" || state.kind === "rejected"
    ? state.message
    : "Your eFlow access could not be verified.";

  return (
    <AppScreen testID="access-denied-screen">
      <View style={{ gap: tokens.space.sm }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Access unavailable
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          eFlow could not safely open this account on mobile.
        </Text>
      </View>
      <StatusNotice tone="danger">{message}</StatusNotice>
      {state.kind === "rejected" ? (
        <View style={{ gap: tokens.space.md }}>
          <Button label="Try again" variant="secondary" onPress={() => void retryAccess()} />
          <Button label="Sign out" onPress={() => void signOut()} />
        </View>
      ) : null}
    </AppScreen>
  );
}

