import type { CanonicalRole } from "@/contracts/roles";
import type { Task } from "@/contracts/tasks";
import {
  canRequestReviewDecision,
  getSubtaskReviewEligibility,
  getTaskReviewEligibility
} from "@/features/reviews/eligibility";

const ids = {
  submitter: "11111111-1111-4111-8111-111111111111",
  primary: "22222222-2222-4222-8222-222222222222",
  backup: "33333333-3333-4333-8333-333333333333",
  outsider: "44444444-4444-4444-8444-444444444444"
};

const task: Pick<Task, "reviewerId" | "backupReviewerId"> = {
  reviewerId: ids.primary,
  backupReviewerId: ids.backup
};

describe("review eligibility", () => {
  it.each<[string, CanonicalRole, string]>([
    [ids.primary, "employee", "primary"],
    [ids.backup, "employee", "backup"],
    [ids.outsider, "employee", "not_assigned"],
    [ids.outsider, "super_admin", "not_assigned"]
  ])("resolves task reviewer %s as %s", (currentUserId, role, expectedKind) => {
    const result = getTaskReviewEligibility(task, { submitterId: ids.submitter }, currentUserId, role);
    expect(result.kind).toBe(expectedKind);
    expect(canRequestReviewDecision(result)).toBe(expectedKind !== "not_assigned");
  });

  it("blocks a primary reviewer who is also the submitter", () => {
    const result = getTaskReviewEligibility(task, { submitterId: ids.primary }, ids.primary, "employee");
    expect(result).toEqual({ kind: "self_review" });
    expect(canRequestReviewDecision(result)).toBe(false);
  });

  it("uses the resolved subtask reviewer and applies the same self-review guard", () => {
    expect(getSubtaskReviewEligibility({ reviewerId: ids.primary, submitterId: ids.submitter }, ids.primary, "employee"))
      .toEqual({ kind: "primary" });
    expect(getSubtaskReviewEligibility({ reviewerId: ids.primary, submitterId: ids.primary }, ids.primary, "super_admin"))
      .toEqual({ kind: "self_review" });
  });
});
