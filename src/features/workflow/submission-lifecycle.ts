import { SupabaseUserError } from "@/lib/supabase/errors";

/**
 * A network/server failure can occur after the database transaction committed.
 * Leaving unverified evidence in place is safer than deleting a finalised
 * submission's files. Only a confirmed rejection may trigger cleanup.
 */
export function mayCleanUpAfterSubmissionFailure(error: unknown): boolean {
  if (!(error instanceof SupabaseUserError)) return false;
  return !["offline", "server", "duplicate"].includes(error.kind);
}

export function submissionFailureMessage(error: unknown): string {
  if (error instanceof SupabaseUserError && !mayCleanUpAfterSubmissionFailure(error)) {
    return "We could not confirm the submission. Refresh before trying again; selected evidence was kept so a completed submission is never deleted.";
  }
  return error instanceof Error ? error.message : "We could not submit this work.";
}
