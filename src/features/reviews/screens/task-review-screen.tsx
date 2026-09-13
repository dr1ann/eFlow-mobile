import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { Task, TaskAttachment, TaskSubmission } from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import { ReviewSubmissionPanel } from "@/features/reviews/components/review-submission-panel";
import { getTaskReviewEligibility, canRequestReviewDecision } from "@/features/reviews/eligibility";
import { getCurrentTaskReviewSubmission } from "@/features/reviews/submission-selection";
import { decideTaskReview } from "@/features/tasks/api/task-workflow-api";
import {
  taskAttachmentsQueryOptions,
  taskDetailQueryOptions,
  taskSubmissionsQueryOptions
} from "@/features/tasks/query-options";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";

interface TaskReviewViewProps {
  task: Pick<Task, "title" | "reviewerId" | "backupReviewerId">;
  submission: TaskSubmission;
  attachments: readonly TaskAttachment[];
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

export function TaskReviewView({ task, submission, ...props }: TaskReviewViewProps) {
  return (
    <ReviewSubmissionPanel
      workKind="task"
      workTitle={task.title}
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

export function TaskReviewScreen({ taskId }: { taskId: string }) {
  const { state } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const submissionsQuery = useQuery({
    ...taskSubmissionsQueryOptions(taskId, 0),
    enabled: taskQuery.isSuccess && taskQuery.data !== null
  });
  const pendingSubmission = getCurrentTaskReviewSubmission(submissionsQuery.data);
  const attachmentsQuery = useQuery({
    ...taskAttachmentsQueryOptions(taskId, pendingSubmission?.id ?? taskId),
    enabled: pendingSubmission !== undefined
  });
  const mutation = useMutation({
    mutationFn: decideTaskReview,
    onSuccess: async (updatedTask, input) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
      queryClient.setQueryData(taskDetailQueryOptions(input.taskId).queryKey, updatedTask);
    }
  });

  if (state.kind !== "authorized") return null;
  if (!isPhase1CapabilityEnabled("taskDecision")) {
    return <AppScreen testID="task-review-gated"><StatusNotice tone="warning">Task review is prepared but disabled until its exact deployed checks are recorded.</StatusNotice></AppScreen>;
  }
  if (taskQuery.isLoading || submissionsQuery.isLoading) {
    return <AppScreen><ActivityIndicator accessibilityLabel="Loading task review" color={colors.primary} /></AppScreen>;
  }
  if (taskQuery.isError || submissionsQuery.isError) {
    return (
      <AppScreen>
        <StatusNotice tone="danger">We could not load this task review. Try again.</StatusNotice>
        <Button
          label="Retry task review"
          onPress={() => {
            void taskQuery.refetch();
            void submissionsQuery.refetch();
          }}
        />
      </AppScreen>
    );
  }
  if (!taskQuery.data || !pendingSubmission) {
    return <AppScreen><StatusNotice tone="danger">This pending task review is unavailable or you do not have access to it.</StatusNotice></AppScreen>;
  }

  const canReview = canRequestReviewDecision(
    getTaskReviewEligibility(taskQuery.data, pendingSubmission, state.profile.id, state.profile.role)
  );
  const canOpenEvidence =
    isPhase1CapabilityEnabled("evidenceRules") && isPhase1CapabilityEnabled("evidenceSignedRead");

  return (
    <TaskReviewView
      task={taskQuery.data}
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
          { taskId, approve, feedback },
          {
            onSuccess: () => {
              router.replace({
                pathname: "/tasks/[task-id]",
                params: { "task-id": taskId }
              });
            }
          }
        );
      }}
      onBack={() => router.back()}
    />
  );
}
