export type SupabaseErrorKind =
  | "offline"
  | "unauthenticated"
  | "forbidden"
  | "not_found"
  | "duplicate"
  | "invalid_state"
  | "validation"
  | "server";

export class SupabaseUserError extends Error {
  constructor(
    readonly kind: SupabaseErrorKind,
    message: string
  ) {
    super(message);
    this.name = "SupabaseUserError";
  }
}

function errorCode(error: unknown): string | null {
  if (typeof error !== "object" || error === null || !("code" in error)) return null;
  const code = error.code;
  return typeof code === "string" ? code : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "";
}

export function toSupabaseUserError(error: unknown): SupabaseUserError {
  if (error instanceof SupabaseUserError) return error;

  const code = errorCode(error);
  if (code === "42501") {
    return new SupabaseUserError("forbidden", "You do not have access to complete this action.");
  }
  if (code === "P0002") {
    return new SupabaseUserError("not_found", "This item is no longer available.");
  }
  if (code === "23505") {
    return new SupabaseUserError("duplicate", "This action has already been recorded. Refresh and try again.");
  }
  if (code === "22023") {
    return new SupabaseUserError("invalid_state", "This action is not available in the item's current state.");
  }
  if (code === "PGRST301") {
    return new SupabaseUserError("unauthenticated", "Your session has expired. Sign in again to continue.");
  }

  const message = errorMessage(error).toLowerCase();
  if (error instanceof TypeError || message.includes("network request failed") || message.includes("network error")) {
    return new SupabaseUserError("offline", "You appear to be offline. Reconnect and try again.");
  }
  if (code === "23514" || code === "22P02") {
    return new SupabaseUserError("validation", "Some details are invalid. Review them and try again.");
  }

  return new SupabaseUserError("server", "We could not complete that request. Try again later.");
}
