import { Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function SettingsScreen() {
  const { state, signOut } = useAuth();
  if (state.kind !== "authorized") return null;

  return (
    <AppScreen testID="settings-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
          Account
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          {state.profile.email}
        </Text>
      </View>
      <StatusNotice>
        Signing out removes the local session, in-memory query cache, discovered gateway endpoint, and foreground Realtime subscriptions.
      </StatusNotice>
      <Button label="Sign out" variant="secondary" onPress={() => void signOut()} />
    </AppScreen>
  );
}

