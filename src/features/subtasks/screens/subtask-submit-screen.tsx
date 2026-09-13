import React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, ScrollView, Text, TextInput, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { EvidencePickerPreview } from "@/features/subtasks/components/evidence-picker-preview";
import { type NativeEvidenceAsset } from "@/features/subtasks/evidence";
import { getTaskEvidenceRules } from "@/features/subtasks/evidence-storage";
import { subtaskDetailQueryOptions } from "@/features/subtasks/query-options";
import { submitSubtaskEvidence } from "@/features/subtasks/subtask-submission";
import { isMySubtask } from "@/features/tasks/selectors";
import { invalidateSubtaskWorkflow } from "@/features/workflow/cache-invalidation";
import { submissionFailureMessage } from "@/features/workflow/submission-lifecycle";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

const evidenceRulesQueryKey = ["phase-1", "evidence-rules"] as const;

export function SubtaskSubmitScreen({ subtaskId }: { subtaskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const subtaskQuery = useQuery(subtaskDetailQueryOptions(subtaskId));
  const enabled = isPhase1CapabilityEnabled("evidenceRules") &&
    isPhase1CapabilityEnabled("evidenceUpload") && isPhase1CapabilityEnabled("subtaskSubmit");
  const rulesQuery = useQuery({ queryKey: evidenceRulesQueryKey, queryFn: getTaskEvidenceRules, enabled });
  const [note, setNote] = React.useState("");
  const [assets, setAssets] = React.useState<readonly NativeEvidenceAsset[]>([]);
  const mutation = useMutation({
    mutationFn: submitSubtaskEvidence,
    onSuccess: async (_value, input) => {
      const subtask = subtaskQuery.data;
      if (subtask) await invalidateSubtaskWorkflow(queryClient, input.subtaskId, subtask.taskId);
    }
  });

  if (state.kind !== "authorized") return null;
  if (!enabled) return <GatedSubmissionNotice />;
  if (subtaskQuery.isLoading || rulesQuery.isLoading) {
    return <AppScreen><ActivityIndicator accessibilityLabel="Preparing subtask submission" color={colors.primary} /></AppScreen>;
  }
  if (!subtaskQuery.data || subtaskQuery.isError || !rulesQuery.data || rulesQuery.isError) {
    return <AppScreen><StatusNotice tone="danger">This subtask or its evidence rules are unavailable. Refresh and try again.</StatusNotice></AppScreen>;
  }

  const editable = ["todo", "in_progress", "changes_requested"].includes(subtaskQuery.data.status);
  const canSubmit = editable && isMySubtask(subtaskQuery.data, state.profile.id);
  const submit = (): void => {
    mutation.mutate(
      { subtaskId, note, assets, rules: rulesQuery.data },
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
    <ScrollView contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled" style={{ flex: 1, backgroundColor: colors.background }} contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}>
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          {subtaskQuery.data.status === "changes_requested" ? "Resubmit subtask" : "Submit subtask"}
        </Text>
        <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>{subtaskQuery.data.title}</Text>
      </View>
      {!canSubmit ? <StatusNotice tone="warning">Only an assigned contributor can submit this editable subtask.</StatusNotice> : <>
        <SubmissionNote value={note} onChangeText={setNote} />
        <EvidencePickerPreview selectedAssets={assets} onSelectedAssetsChange={setAssets} maximumFiles={rulesQuery.data.maximumFilesPerSubmission} submissionMode />
        {!note.trim() ? <StatusNotice tone="warning">Add a completion note before submitting this subtask.</StatusNotice> : null}
        {mutation.error ? <StatusNotice tone="danger">{submissionFailureMessage(mutation.error)}</StatusNotice> : null}
        <StatusNotice>Submitting is online-only. The reviewer and final evidence state are decided by the server.</StatusNotice>
        <Button
          label={subtaskQuery.data.status === "changes_requested" ? "Resubmit for review" : "Submit for review"}
          loading={mutation.isPending}
          disabled={!note.trim()}
          onPress={submit}
        />
      </>}
    </ScrollView>
  );
}

export function GatedSubmissionNotice() {
  return <AppScreen testID="subtask-submit-gated"><StatusNotice tone="warning">Evidence-backed submission is ready in the app but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
}

export function SubmissionNote({ value, onChangeText }: { value: string; onChangeText(value: string): void }) {
  return <View style={{ gap: tokens.space.xs }}>
    <Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>Completion note</Text>
    <TextInput accessibilityLabel="Completion note" value={value} onChangeText={onChangeText} multiline maxLength={2000} textAlignVertical="top" style={{ minHeight: 120, padding: tokens.space.md, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, color: colors.label, backgroundColor: colors.surface }} />
  </View>;
}
