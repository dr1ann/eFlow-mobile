import React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, Alert, ScrollView, Text, TextInput, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { useAuth } from "@/features/auth/auth-context";
import { decideSubtaskReview } from "@/features/subtasks/api/subtask-workflow-api";
import { subtaskSubmissionsQueryOptions, subtaskDetailQueryOptions } from "@/features/subtasks/query-options";
import { invalidateSubtaskWorkflow } from "@/features/workflow/cache-invalidation";
import { getSubtaskReviewEligibility, canRequestReviewDecision } from "@/features/reviews/eligibility";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

function reviewError(error: unknown): string {
  return error instanceof SupabaseUserError ? error.message : "We could not record this decision. Refresh to confirm the current review state.";
}

export function SubtaskReviewScreen({ subtaskId }: { subtaskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const subtaskQuery = useQuery(subtaskDetailQueryOptions(subtaskId));
  const submissionsQuery = useQuery({ ...subtaskSubmissionsQueryOptions(subtaskId, 0), enabled: subtaskQuery.isSuccess && subtaskQuery.data !== null });
  const [feedback, setFeedback] = React.useState("");
  const mutation = useMutation({
    mutationFn: decideSubtaskReview,
    onSuccess: async (_value, input) => {
      const subtask = subtaskQuery.data;
      if (subtask) await invalidateSubtaskWorkflow(queryClient, input.subtaskId, subtask.taskId);
    }
  });

  if (state.kind !== "authorized") return null;
  if (!isPhase1CapabilityEnabled("subtaskDecision")) {
    return <AppScreen testID="subtask-review-gated"><StatusNotice tone="warning">Subtask review is prepared but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
  }
  if (subtaskQuery.isLoading || submissionsQuery.isLoading) return <AppScreen><ActivityIndicator accessibilityLabel="Loading subtask review" color={colors.primary} /></AppScreen>;
  const submission = submissionsQuery.data?.find((item) => item.status === "pending");
  if (!subtaskQuery.data || !submission || subtaskQuery.isError || submissionsQuery.isError) {
    return <AppScreen><StatusNotice tone="danger">This pending subtask review is unavailable or you do not have access to it.</StatusNotice></AppScreen>;
  }

  const eligibility = getSubtaskReviewEligibility(submission, state.profile.id, state.profile.role);
  const canReview = canRequestReviewDecision(eligibility);
  const decide = (approve: boolean): void => {
    if (!approve && !feedback.trim()) return;
    const action = approve ? "approve" : "request changes to";
    Alert.alert(
      `${approve ? "Approve" : "Request changes"} subtask`,
      `This will immediately ${action} this submission through the server.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: approve ? "Approve" : "Request changes",
          style: approve ? "default" : "destructive",
          onPress: () =>
            mutation.mutate(
              { subtaskId, approve, feedback },
              {
                onSuccess: () => {
                  router.replace({
                    pathname: "/subtasks/[subtask-id]",
                    params: { "subtask-id": subtaskId }
                  });
                }
              }
            )
        }
      ]
    );
  };

  return <ScrollView contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled" style={{ flex: 1, backgroundColor: colors.background }} contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}>
    <View style={{ gap: tokens.space.xs }}>
      <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Review subtask</Text>
      <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>{subtaskQuery.data.title} · Version {submission.version}</Text>
    </View>
    <StatusNotice>Submitted by {submission.submitterName}. Evidence and prior attempts remain immutable.</StatusNotice>
    {!canReview ? <StatusNotice tone="danger">You are not the resolved reviewer for this submission.</StatusNotice> : <>
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>Feedback {"(required for changes)"}</Text>
        <TextInput accessibilityLabel="Review feedback" value={feedback} onChangeText={setFeedback} multiline maxLength={2000} textAlignVertical="top" style={{ minHeight: 120, padding: tokens.space.md, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, color: colors.label, backgroundColor: colors.surface }} />
      </View>
      {mutation.error ? <StatusNotice tone="danger">{reviewError(mutation.error)}</StatusNotice> : null}
      <Button label="Approve subtask" loading={mutation.isPending} onPress={() => decide(true)} />
      <Button label="Request changes" variant="danger" disabled={!feedback.trim()} onPress={() => decide(false)} />
    </>}
    <Button label="Back to subtask" variant="secondary" onPress={() => router.back()} />
  </ScrollView>;
}
