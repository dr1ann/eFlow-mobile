import { Color } from "expo-router";
import type { ColorValue } from "react-native";

type NativeColor = ColorValue;

function nativeColor(ios: NativeColor, android: NativeColor, fallback: string): NativeColor {
  if (process.env.EXPO_OS === "ios") return ios;
  if (process.env.EXPO_OS === "android") return android;
  return fallback;
}

export const colors = {
  background: nativeColor(
    Color.ios.systemBackground,
    Color.android.dynamic.surface,
    "#F8FAFC"
  ),
  surface: nativeColor(
    Color.ios.systemBackground,
    Color.android.dynamic.surface,
    "#FFFFFF"
  ),
  label: nativeColor(Color.ios.label, Color.android.dynamic.onSurface, "#0F172A"),
  secondaryLabel: nativeColor(
    Color.ios.secondaryLabel,
    Color.android.dynamic.onSurfaceVariant,
    "#475569"
  ),
  separator: nativeColor(
    Color.ios.separator,
    Color.android.dynamic.outlineVariant,
    "#CBD5E1"
  ),
  primary: nativeColor(
    Color.ios.systemBlue,
    Color.android.dynamic.primary,
    "#2563EB"
  ),
  onPrimary: "#FFFFFF",
  danger: "#DC2626",
  success: "#15803D",
  warning: "#B45309"
} as const;
