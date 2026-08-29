export type ReviewDecision = "approve" | "request_changes";

export type ReviewEligibility =
  | { kind: "primary" }
  | { kind: "backup" }
  | { kind: "administrator" }
  | { kind: "self_review" }
  | { kind: "not_assigned" };

export function reviewDecisionLabel(decision: ReviewDecision): string {
  return decision === "approve" ? "Approve" : "Request changes";
}
