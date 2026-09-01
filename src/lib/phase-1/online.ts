import { onlineManager } from "@tanstack/react-query";

import { SupabaseUserError } from "@/lib/supabase/errors";

/** Sensitive workflow mutations must be initiated while connectivity is known. */
export function requireOnlineMutation(isOnline: boolean | undefined): void {
  if (isOnline === true) return;
  throw new SupabaseUserError(
    "offline",
    "Reconnect before making this change. It will not be queued automatically."
  );
}

export function requireCurrentOnlineMutation(): void {
  requireOnlineMutation(onlineManager.isOnline());
}
