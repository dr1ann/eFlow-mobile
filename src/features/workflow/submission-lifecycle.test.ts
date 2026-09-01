import {
  mayCleanUpAfterSubmissionFailure,
  submissionFailureMessage
} from "@/features/workflow/submission-lifecycle";
import { SupabaseUserError } from "@/lib/supabase/errors";

describe("evidence submission failure handling", () => {
  it("does not delete evidence after an ambiguous timeout, network, or duplicate result", () => {
    for (const kind of ["offline", "server", "duplicate"] as const) {
      expect(mayCleanUpAfterSubmissionFailure(new SupabaseUserError(kind, "redacted"))).toBe(false);
    }
    expect(submissionFailureMessage(new SupabaseUserError("offline", "redacted"))).toMatch(/never deleted/i);
  });

  it("allows claim-before-delete cleanup only after a confirmed rejection", () => {
    expect(mayCleanUpAfterSubmissionFailure(new SupabaseUserError("validation", "bad input"))).toBe(true);
    expect(mayCleanUpAfterSubmissionFailure(new Error("unknown"))).toBe(false);
  });
});
