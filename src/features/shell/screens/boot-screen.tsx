import { ActivityIndicator, Text, View } from "react-native";

import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function BootScreen() {
  return (
    <View
      accessibilityRole="progressbar"
      accessibilityLabel="Restoring eFlow session"
      style={{
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
        gap: tokens.space.md,
        backgroundColor: colors.background,
        padding: tokens.space.xl
      }}
    >
      <ActivityIndicator color={colors.primary} size="large" />
      <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
        Restoring your secure eFlow session…
      </Text>
    </View>
  );
}

