import React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, Alert, ScrollView, Text, TextInput, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { decideTaskReview } from "@/features/tasks/api/task-workflow-api";
import { taskSubmissionsQueryOptions, taskDetailQueryOptions } from "@/features/tasks/query-options";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";
import { getTaskReviewEligibility, canRequestReviewDecision } from "@/features/reviews/eligibility";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function TaskReviewScreen({ taskId }: { taskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const submissionsQuery = useQuery({ ...taskSubmissionsQueryOptions(taskId, 0), enabled: taskQuery.isSuccess && taskQuery.data !== null });
  const [feedback, setFeedback] = React.useState("");
  const mutation = useMutation({
    mutationFn: decideTaskReview,
    onSuccess: async (_value, input) => { await invalidateTaskWorkflow(queryClient, input.taskId); }
  });

  if (state.kind !== "authorized") return null;
  if (!isPhase1CapabilityEnabled("taskDecision")) return <AppScreen testID="task-review-gated"><StatusNotice tone="warning">Task review is prepared but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
  if (taskQuery.isLoading || submissionsQuery.isLoading) return <AppScreen><ActivityIndicator accessibilityLabel="Loading task review" color={colors.primary} /></AppScreen>;
  const submission = submissionsQuery.data?.find((item) => item.status === "pending");
  if (!taskQuery.data || !submission || taskQuery.isError || submissionsQuery.isError) return <AppScreen><StatusNotice tone="danger">This pending task review is unavailable or you do not have access to it.</StatusNotice></AppScreen>;

  const canReview = canRequestReviewDecision(getTaskReviewEligibility(taskQuery.data, submission, state.profile.id, state.profile.role));
  const decide = (approve: boolean): void => {
    if (!approve && !feedback.trim()) return;
    Alert.alert(`${approve ? "Approve" : "Request changes"} task`, "This immediately records the decision through the server.", [
      { text: "Cancel", style: "cancel" },
      {
        text: approve ? "Approve" : "Request changes",
        style: approve ? "default" : "destructive",
        onPress: () =>
          mutation.mutate(
            { taskId, approve, feedback },
            {
              onSuccess: () => {
                router.replace({
                  pathname: "/tasks/[task-id]",
                  params: { "task-id": taskId }
                });
              }
            }
          )
      }
    ]);
  };

  return <ScrollView contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled" style={{ flex: 1, backgroundColor: colors.background }} contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}>
    <View style={{ gap: tokens.space.xs }}><Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Review task</Text><Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>{taskQuery.data.title} · Version {submission.version}</Text></View>
    <StatusNotice>Submitted by {submission.submitterName}. Evidence and prior attempts remain immutable.</StatusNotice>
    {!canReview ? <StatusNotice tone="danger">You are not the resolved reviewer for this submission.</StatusNotice> : <>
      <View style={{ gap: tokens.space.xs }}><Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>Feedback {"(required for changes)"}</Text><TextInput accessibilityLabel="Review feedback" value={feedback} onChangeText={setFeedback} multiline maxLength={2000} textAlignVertical="top" style={{ minHeight: 120, padding: tokens.space.md, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, color: colors.label, backgroundColor: colors.surface }} /></View>
      {mutation.error ? <StatusNotice tone="danger">{mutation.error instanceof SupabaseUserError ? mutation.error.message : "We could not record this decision. Refresh to confirm the current review state."}</StatusNotice> : null}
      <Button label="Approve task" loading={mutation.isPending} onPress={() => decide(true)} />
      <Button label="Request changes" variant="danger" disabled={!feedback.trim()} onPress={() => decide(false)} />
    </>}
    <Button label="Back to task" variant="secondary" onPress={() => router.back()} />
  </ScrollView>;
}
