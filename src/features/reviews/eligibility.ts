import type { ReviewEligibility } from "@/contracts/reviews";
import type { SubtaskSubmission } from "@/contracts/subtasks";
import type { Task, TaskSubmission } from "@/contracts/tasks";

interface EligibilityContext {
  currentUserId: string;
  submitterId: string;
}

function resolveEligibility(
  context: EligibilityContext,
  primaryReviewerId: string | null,
  backupReviewerId: string | null = null
): ReviewEligibility {
  if (context.currentUserId === context.submitterId) return { kind: "self_review" };
  if (context.currentUserId === primaryReviewerId) return { kind: "primary" };
  if (context.currentUserId === backupReviewerId) return { kind: "backup" };
  // Operational task decisions are never exposed to a Super Admin solely by
  // virtue of that role. A stored review route is required.
  return { kind: "not_assigned" };
}

export function getTaskReviewEligibility(
  task: Pick<Task, "reviewerId" | "backupReviewerId">,
  submission: Pick<TaskSubmission, "submitterId">,
  currentUserId: string,
  _role: import("@/contracts/roles").CanonicalRole
): ReviewEligibility {
  return resolveEligibility(
    { currentUserId, submitterId: submission.submitterId },
    task.reviewerId,
    task.backupReviewerId
  );
}

export function getSubtaskReviewEligibility(
  submission: Pick<SubtaskSubmission, "reviewerId" | "submitterId">,
  currentUserId: string,
  _role: import("@/contracts/roles").CanonicalRole
): ReviewEligibility {
  return resolveEligibility(
    { currentUserId, submitterId: submission.submitterId },
    submission.reviewerId
  );
}

export function canRequestReviewDecision(eligibility: ReviewEligibility): boolean {
  return eligibility.kind === "primary" || eligibility.kind === "backup";
}
