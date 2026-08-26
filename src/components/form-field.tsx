import { Text, TextInput, View, type TextInputProps } from "react-native";

import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface FormFieldProps extends TextInputProps {
  label: string;
  error?: string;
}

export function FormField({ label, error, ...inputProps }: FormFieldProps) {
  return (
    <View style={{ gap: tokens.space.sm }}>
      <Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>
        {label}
      </Text>
      <TextInput
        {...inputProps}
        accessibilityLabel={label}
        accessibilityHint={error ? `Error: ${error}` : inputProps.accessibilityHint}
        placeholderTextColor={colors.secondaryLabel}
        style={{
          minHeight: tokens.touchTarget,
          borderWidth: 1,
          borderColor: error ? colors.danger : colors.separator,
          borderRadius: tokens.radius.md,
          borderCurve: "continuous",
          color: colors.label,
          backgroundColor: colors.surface,
          paddingHorizontal: tokens.space.md,
          fontSize: tokens.type.body
        }}
      />
      {error ? (
        <Text selectable style={{ color: colors.danger, fontSize: tokens.type.caption }}>
          {error}
        </Text>
      ) : null}
    </View>
  );
}
