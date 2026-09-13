import type { Subtask, SubtaskSubmission } from "@/contracts/subtasks";
import type { TaskSubmission } from "@/contracts/tasks";

/** The task API orders attempts newest-first; only its latest pending row is reviewable. */
export function getCurrentTaskReviewSubmission(
  submissions: readonly TaskSubmission[] | undefined
): TaskSubmission | undefined {
  const latestSubmission = submissions?.[0];
  return latestSubmission?.status === "pending" ? latestSubmission : undefined;
}

/** The server marks a subtask's canonical latest attempt; historic pending rows are never reviewable. */
export function getCurrentSubtaskReviewSubmission(
  subtask: Pick<Subtask, "latestSubmissionId"> | null | undefined,
  submissions: readonly SubtaskSubmission[] | undefined
): SubtaskSubmission | undefined {
  if (!subtask?.latestSubmissionId) return undefined;
  const latestSubmission = submissions?.find(
    (submission) => submission.id === subtask.latestSubmissionId
  );
  return latestSubmission?.status === "pending" ? latestSubmission : undefined;
}
