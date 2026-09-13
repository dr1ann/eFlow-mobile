import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { Subtask, SubtaskSubmission, SubtaskSubmissionAttachment } from "@/contracts/subtasks";
import { useAuth } from "@/features/auth/auth-context";
import { ReviewSubmissionPanel } from "@/features/reviews/components/review-submission-panel";
import { getSubtaskReviewEligibility, canRequestReviewDecision } from "@/features/reviews/eligibility";
import { getCurrentSubtaskReviewSubmission } from "@/features/reviews/submission-selection";
import { decideSubtaskReview } from "@/features/subtasks/api/subtask-workflow-api";
import {
  subtaskDetailQueryOptions,
  subtaskSubmissionAttachmentsQueryOptions,
  subtaskSubmissionsQueryOptions
} from "@/features/subtasks/query-options";
import { invalidateSubtaskWorkflow } from "@/features/workflow/cache-invalidation";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";

interface SubtaskReviewViewProps {
  subtask: Pick<Subtask, "title">;
  submission: SubtaskSubmission;
  attachments: readonly SubtaskSubmissionAttachment[];
  attachmentsLoading: boolean;
  attachmentsError: boolean;
  canOpenEvidence: boolean;
  canReview: boolean;
  decisionPending: boolean;
  decisionError: string | null;
  onRetryAttachments(): void;
  onDecide(approve: boolean, feedback: string): void;
  onBack(): void;
}

export function SubtaskReviewView({ subtask, submission, ...props }: SubtaskReviewViewProps) {
  return (
    <ReviewSubmissionPanel
      workKind="subtask"
      workTitle={subtask.title}
      submission={submission}
      {...props}
    />
  );
}

function reviewError(error: unknown): string {
  return error instanceof SupabaseUserError
    ? error.message
    : "We could not record this decision. Refresh to confirm the current review state.";
}

export function SubtaskReviewScreen({ subtaskId }: { subtaskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const subtaskQuery = useQuery(subtaskDetailQueryOptions(subtaskId));
  const submissionsQuery = useQuery({
    ...subtaskSubmissionsQueryOptions(subtaskId, 0),
    enabled: subtaskQuery.isSuccess && subtaskQuery.data !== null
  });
  const pendingSubmission = getCurrentSubtaskReviewSubmission(subtaskQuery.data, submissionsQuery.data);
  const attachmentsQuery = useQuery({
    ...subtaskSubmissionAttachmentsQueryOptions(pendingSubmission?.id ?? subtaskId),
    enabled: pendingSubmission !== undefined
  });
  const mutation = useMutation({
    mutationFn: decideSubtaskReview,
    onSuccess: async (updatedSubtask, input) => {
      const subtask = subtaskQuery.data;
      if (!subtask) return;
      await invalidateSubtaskWorkflow(queryClient, input.subtaskId, subtask.taskId);
      queryClient.setQueryData(subtaskDetailQueryOptions(input.subtaskId).queryKey, updatedSubtask);
    }
  });

  if (state.kind !== "authorized") return null;
  if (!isPhase1CapabilityEnabled("subtaskDecision")) {
    return <AppScreen testID="subtask-review-gated"><StatusNotice tone="warning">Subtask review is prepared but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
  }
  if (subtaskQuery.isLoading || submissionsQuery.isLoading) {
    return <AppScreen><ActivityIndicator accessibilityLabel="Loading subtask review" color={colors.primary} /></AppScreen>;
  }
  if (subtaskQuery.isError || submissionsQuery.isError) {
    return (
      <AppScreen>
        <StatusNotice tone="danger">We could not load this subtask review. Try again.</StatusNotice>
        <Button
          label="Retry subtask review"
          onPress={() => {
            void subtaskQuery.refetch();
            void submissionsQuery.refetch();
          }}
        />
      </AppScreen>
    );
  }
  if (!subtaskQuery.data || !pendingSubmission) {
    return <AppScreen><StatusNotice tone="danger">This pending subtask review is unavailable or you do not have access to it.</StatusNotice></AppScreen>;
  }

  const canReview = canRequestReviewDecision(
    getSubtaskReviewEligibility(pendingSubmission, state.profile.id, state.profile.role)
  );
  const canOpenEvidence =
    isPhase1CapabilityEnabled("evidenceRules") && isPhase1CapabilityEnabled("evidenceSignedRead");

  return (
    <SubtaskReviewView
      subtask={subtaskQuery.data}
      submission={pendingSubmission}
      attachments={attachmentsQuery.data ?? []}
      attachmentsLoading={attachmentsQuery.isLoading}
      attachmentsError={attachmentsQuery.isError}
      canOpenEvidence={canOpenEvidence}
      canReview={canReview}
      decisionPending={mutation.isPending}
      decisionError={mutation.error ? reviewError(mutation.error) : null}
      onRetryAttachments={() => void attachmentsQuery.refetch()}
      onDecide={(approve, feedback) => {
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
        );
      }}
      onBack={() => router.back()}
    />
  );
}
