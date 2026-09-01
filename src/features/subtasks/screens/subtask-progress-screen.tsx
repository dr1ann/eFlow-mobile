import React from "react";
import { useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, ScrollView, Text, TextInput, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { subtaskStatusLabel } from "@/contracts/subtasks";
import { useAuth } from "@/features/auth/auth-context";
import { subtaskDetailQueryOptions } from "@/features/subtasks/query-options";
import { useSaveSubtaskProgressMutation } from "@/features/subtasks/use-subtask-workflow";
import { isMySubtask } from "@/features/tasks/selectors";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

function mutationMessage(error: unknown): string {
  if (error instanceof SupabaseUserError) return error.message;
  if (error instanceof Error) return error.message;
  return "We could not save progress. Try again when you are connected.";
}

export function SubtaskProgressScreen({ subtaskId }: { subtaskId: string }) {
  const router = useRouter();
  const { state } = useAuth();
  const query = useQuery(subtaskDetailQueryOptions(subtaskId));
  const taskId = query.data?.taskId ?? "";
  const mutation = useSaveSubtaskProgressMutation(taskId);
  const [percent, setPercent] = React.useState("");
  const [blockerCategory, setBlockerCategory] = React.useState("");
  const [blocker, setBlocker] = React.useState("");
  const [nextStep, setNextStep] = React.useState("");
  const [note, setNote] = React.useState("");
  const [validationMessage, setValidationMessage] = React.useState<string | null>(null);

  if (state.kind !== "authorized") return null;

  if (!isPhase1CapabilityEnabled("subtaskProgress")) {
    return (
      <AppScreen testID="subtask-progress-gated">
        <StatusNotice tone="warning">
          Progress saving is prepared but remains disabled until its deployed allowed/denied check is recorded.
        </StatusNotice>
      </AppScreen>
    );
  }

  if (query.isLoading) {
    return <AppScreen><ActivityIndicator accessibilityLabel="Loading subtask" color={colors.primary} /></AppScreen>;
  }
  if (!query.data || query.isError) {
    return (
      <AppScreen>
        <StatusNotice tone="danger">This subtask is unavailable or you do not have access to it.</StatusNotice>
      </AppScreen>
    );
  }

  const editable = query.data.status === "todo" || query.data.status === "in_progress" || query.data.status === "changes_requested";
  const assigned = isMySubtask(query.data, state.profile.id);
  const onSave = (): void => {
    const value = Number(percent);
    if (!Number.isInteger(value) || value < 0 || value >= 100) {
      setValidationMessage("Enter a whole-number progress value from 0 to 99. Submit the work for review at 100%.");
      return;
    }
    setValidationMessage(null);
    mutation.mutate(
      {
        subtaskId,
        percentComplete: value,
        blockerCategory,
        blocker,
        nextStep,
        note
      },
      {
        onSuccess: () => {
          router.replace({
            pathname: "/subtasks/[subtask-id]",
            params: { "subtask-id": subtaskId }
          });
        }
      }
    );
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}
    >
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Update progress</Text>
        <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          {query.data.title} · {subtaskStatusLabel(query.data.status)}
        </Text>
      </View>
      {!assigned || !editable ? (
        <StatusNotice tone="warning">Only an assigned contributor can update an editable subtask.</StatusNotice>
      ) : (
        <>
          <ProgressField label="Progress (0–99%)" value={percent} onChangeText={setPercent} keyboardType="number-pad" />
          <ProgressField label="Blocker category (optional)" value={blockerCategory} onChangeText={setBlockerCategory} />
          <ProgressField label="Blocker details (optional)" value={blocker} onChangeText={setBlocker} multiline />
          <ProgressField label="Next step (optional)" value={nextStep} onChangeText={setNextStep} multiline />
          <ProgressField label="Progress note (optional)" value={note} onChangeText={setNote} multiline />
          {validationMessage ? <StatusNotice tone="danger">{validationMessage}</StatusNotice> : null}
          {mutation.error ? <StatusNotice tone="danger">{mutationMessage(mutation.error)}</StatusNotice> : null}
          <StatusNotice>Progress writes are online-only and are never queued for a later replay.</StatusNotice>
          <Button label="Save progress" loading={mutation.isPending} onPress={onSave} />
        </>
      )}
    </ScrollView>
  );
}

function ProgressField({
  label,
  multiline = false,
  ...input
}: {
  label: string;
  value: string;
  onChangeText(value: string): void;
  keyboardType?: "default" | "number-pad";
  multiline?: boolean;
}) {
  return (
    <View style={{ gap: tokens.space.xs }}>
      <Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        value={input.value}
        onChangeText={input.onChangeText}
        keyboardType={input.keyboardType}
        multiline={multiline}
        maxLength={multiline ? 1000 : 120}
        style={{
          minHeight: multiline ? 96 : tokens.touchTarget,
          paddingHorizontal: tokens.space.md,
          paddingVertical: tokens.space.sm,
          borderRadius: tokens.radius.md,
          borderWidth: 1,
          borderColor: colors.separator,
          color: colors.label,
          backgroundColor: colors.surface,
          textAlignVertical: multiline ? "top" : "center"
        }}
      />
    </View>
  );
}
