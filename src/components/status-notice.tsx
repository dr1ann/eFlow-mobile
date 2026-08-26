import type { PropsWithChildren } from "react";
import { Text, View } from "react-native";

import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function StatusNotice({
  children,
  tone = "neutral"
}: PropsWithChildren<{ tone?: "neutral" | "success" | "warning" | "danger" }>) {
  const color =
    tone === "success" ? colors.success : tone === "warning" ? colors.warning : tone === "danger" ? colors.danger : colors.secondaryLabel;

  return (
    <View
      style={{
        gap: tokens.space.xs,
        padding: tokens.space.md,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: color,
        backgroundColor: colors.surface
      }}
    >
      <Text selectable style={{ color, fontSize: tokens.type.body, lineHeight: 22 }}>
        {children}
      </Text>
    </View>
  );
}

