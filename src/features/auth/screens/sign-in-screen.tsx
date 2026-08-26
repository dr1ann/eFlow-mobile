import React from "react";
import { KeyboardAvoidingView, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { FormField } from "@/components/form-field";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function SignInScreen() {
  const { signIn } = useAuth();
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();
  const [submitting, setSubmitting] = React.useState(false);

  const submit = async (): Promise<void> => {
    const normalizedEmail = email.trim();
    if (!normalizedEmail || !password) {
      setError("Enter your eFlow email and password.");
      return;
    }

    setSubmitting(true);
    setError(undefined);
    try {
      await signIn(normalizedEmail, password);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Sign-in failed.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AppScreen testID="sign-in-screen">
      <KeyboardAvoidingView
        behavior={process.env.EXPO_OS === "ios" ? "padding" : undefined}
        style={{ flex: 1, justifyContent: "center", gap: tokens.space.xl }}
      >
        <View style={{ gap: tokens.space.sm }}>
          <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
            eFlow
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 23 }}>
            Sign in to access your authorized work and reviews.
          </Text>
        </View>

        {error ? <StatusNotice tone="danger">{error}</StatusNotice> : null}

        <View style={{ gap: tokens.space.lg }}>
          <FormField
            label="Email"
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="email"
            keyboardType="email-address"
            textContentType="username"
            returnKeyType="next"
            editable={!submitting}
            placeholder="you@example.gov"
          />
          <FormField
            label="Password"
            value={password}
            onChangeText={setPassword}
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="current-password"
            textContentType="password"
            secureTextEntry
            returnKeyType="go"
            onSubmitEditing={() => void submit()}
            editable={!submitting}
            placeholder="Your password"
          />
          <Button label="Sign in" onPress={() => void submit()} loading={submitting} />
        </View>
      </KeyboardAvoidingView>
    </AppScreen>
  );
}

