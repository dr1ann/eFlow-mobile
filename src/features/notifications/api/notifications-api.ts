import type { Notification } from "@/contracts/notifications";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapNotificationRow } from "../mappers";

export const NOTIFICATION_PAGE_SIZE = 25;

// Deliberately excludes financial and other out-of-scope metadata. The server's
// RLS remains the authorization boundary; user_id is repeated as a defense-in-
// depth recipient scope for every mobile query.
export const NOTIFICATION_SELECT =
  "id,user_id,type,title,message,read,created_at,task_id,project_id,actor_id,actor_name,reason";

export interface NotificationPageRequest {
  page: number;
  signal?: AbortSignal;
}

export function notificationPageRange(page: number): [number, number] {
  const start = Math.max(0, page) * NOTIFICATION_PAGE_SIZE;
  return [start, start + NOTIFICATION_PAGE_SIZE - 1];
}

export async function listNotifications(
  userId: string,
  { page, signal }: NotificationPageRequest
): Promise<readonly Notification[]> {
  const [from, to] = notificationPageRange(page);
  const request = getSupabaseClient()
    .from("notifications")
    .select(NOTIFICATION_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false, nullsFirst: false })
    .order("id", { ascending: true })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapNotificationRow);
}

/**
 * Reads a canonical inbox row for the active recipient before any future push
 * response is resolved. It intentionally does not mark the row read because
 * recipient-only update RLS and an atomic read-state contract are not verified.
 */
export async function getNotificationForRecipient(
  notificationId: string,
  userId: string,
  signal?: AbortSignal
): Promise<Notification | null> {
  let request = getSupabaseClient()
    .from("notifications")
    .select(NOTIFICATION_SELECT)
    .eq("id", notificationId)
    .eq("user_id", userId);
  if (signal) request = request.abortSignal(signal);

  const { data, error } = await request.maybeSingle();
  if (error) throw toSupabaseUserError(error);
  return data ? mapNotificationRow(data) : null;
}
