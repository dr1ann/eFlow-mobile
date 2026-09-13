import React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, ScrollView, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { EvidencePickerPreview } from "@/features/subtasks/components/evidence-picker-preview";
import { type NativeEvidenceAsset } from "@/features/subtasks/evidence";
import { getTaskEvidenceRules } from "@/features/subtasks/evidence-storage";
import { SubmissionNote } from "@/features/subtasks/screens/subtask-submit-screen";
import { subtasksByTaskQueryOptions } from "@/features/subtasks/query-options";
import { taskDetailQueryOptions } from "@/features/tasks/query-options";
import { isTaskLead, getTaskSubmissionReadiness } from "@/features/tasks/selectors";
import { submitTaskEvidence } from "@/features/tasks/task-submission";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";
import { submissionFailureMessage } from "@/features/workflow/submission-lifecycle";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

const evidenceRulesQueryKey = ["phase-1", "evidence-rules"] as const;

export function TaskSubmitScreen({ taskId }: { taskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const subtasksQuery = useQuery({ ...subtasksByTaskQueryOptions(taskId), enabled: taskQuery.data !== null && taskQuery.isSuccess });
  const enabled = isPhase1CapabilityEnabled("evidenceRules") &&
    isPhase1CapabilityEnabled("evidenceUpload") && isPhase1CapabilityEnabled("taskSubmit");
  const rulesQuery = useQuery({ queryKey: evidenceRulesQueryKey, queryFn: getTaskEvidenceRules, enabled });
  const [note, setNote] = React.useState("");
  const [assets, setAssets] = React.useState<readonly NativeEvidenceAsset[]>([]);
  const mutation = useMutation({
    mutationFn: submitTaskEvidence,
    onSuccess: async (_value, input) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });

  if (state.kind !== "authorized") return null;
  if (!enabled) {
    return <AppScreen testID="task-submit-gated"><StatusNotice tone="warning">Parent submission is prepared but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
  }
  if (taskQuery.isLoading || rulesQuery.isLoading) {
    return <AppScreen><ActivityIndicator accessibilityLabel="Preparing task submission" color={colors.primary} /></AppScreen>;
  }
  if (!taskQuery.data || taskQuery.isError || !rulesQuery.data || rulesQuery.isError) {
    return <AppScreen><StatusNotice tone="danger">This task or its evidence rules are unavailable. Refresh and try again.</StatusNotice></AppScreen>;
  }

  const readiness = getTaskSubmissionReadiness(subtasksQuery.data ?? []);
  const canSubmit =
    taskQuery.data.status === "in_progress" &&
    isTaskLead(taskQuery.data, state.profile.id) &&
    readiness.canSubmit;
  const submit = (): void => {
    mutation.mutate(
      { taskId, note, assets, rules: rulesQuery.data },
      {
        onSuccess: () => {
          router.replace({
            pathname: "/tasks/[task-id]",
            params: { "task-id": taskId }
          });
        }
      }
    );
  };

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled" style={{ flex: 1, backgroundColor: colors.background }} contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}>
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Submit task</Text>
        <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>{taskQuery.data.title}</Text>
      </View>
      {!readiness.canSubmit ? <StatusNotice tone="warning">{readiness.approvedSubtasks} of {readiness.totalSubtasks} subtasks are approved. Every subtask must be approved before this task can be submitted.</StatusNotice> : null}
      {!canSubmit ? <StatusNotice tone="warning">
        {taskQuery.data.status === "changes_requested"
          ? "Resume this task before submitting corrected evidence for review."
          : "Only the effective Task Lead can submit an in-progress task that is ready for review."}
      </StatusNotice> : <>
        <SubmissionNote value={note} onChangeText={setNote} />
        <EvidencePickerPreview selectedAssets={assets} onSelectedAssetsChange={setAssets} maximumFiles={rulesQuery.data.maximumFilesPerSubmission} submissionMode />
        {!note.trim() ? <StatusNotice tone="warning">Add a completion note before submitting this task.</StatusNotice> : null}
        <StatusNotice>Task evidence is optional. Any selected file must pass the same private server rules.</StatusNotice>
        {mutation.error ? <StatusNotice tone="danger">{submissionFailureMessage(mutation.error)}</StatusNotice> : null}
        <Button
          label="Submit task for review"
          loading={mutation.isPending}
          disabled={!note.trim()}
          onPress={submit}
        />
      </>}
    </ScrollView>
  );
}
