import { ActivityIndicator, Pressable, Text, type GestureResponderEvent } from "react-native";

import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface ButtonProps {
  label: string;
  onPress: (event: GestureResponderEvent) => void;
  variant?: "primary" | "secondary" | "danger";
  loading?: boolean;
  disabled?: boolean;
  testID?: string;
}

export function Button({
  label,
  onPress,
  variant = "primary",
  loading = false,
  disabled = false,
  testID
}: ButtonProps) {
  const isPrimary = variant === "primary";
  const isDanger = variant === "danger";
  const backgroundColor = isPrimary
    ? colors.primary
    : isDanger
      ? colors.danger
      : colors.surface;
  const foregroundColor = isPrimary || isDanger ? colors.onPrimary : colors.label;

  return (
    <Pressable
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: disabled || loading, busy: loading }}
      disabled={disabled || loading}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: tokens.touchTarget,
        alignItems: "center",
        justifyContent: "center",
        paddingHorizontal: tokens.space.lg,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: isPrimary || isDanger ? 0 : 1,
        borderColor: colors.separator,
        backgroundColor,
        opacity: disabled || loading ? 0.55 : pressed ? 0.78 : 1
      })}
    >
      {loading ? (
        <ActivityIndicator color={foregroundColor} />
      ) : (
        <Text style={{ color: foregroundColor, fontSize: tokens.type.body, fontWeight: "700" }}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

