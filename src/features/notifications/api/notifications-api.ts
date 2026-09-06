import type { Notification } from "@/contracts/notifications";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { SupabaseUserError, toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapNotificationRow } from "../mappers";

export const NOTIFICATION_PAGE_SIZE = 25;
export const NOTIFICATION_FILTERS = ["all", "unread"] as const;
export type NotificationFilter = (typeof NOTIFICATION_FILTERS)[number];

// Deliberately excludes financial and other out-of-scope metadata. The server's
// RLS remains the authorization boundary; user_id is repeated as a defense-in-
// depth recipient scope for every mobile query.
export const NOTIFICATION_SELECT =
  "id,user_id,type,title,message,read,created_at,task_id,project_id,actor_id,actor_name,reason";

export interface NotificationPageRequest {
  filter?: NotificationFilter;
  page: number;
  signal?: AbortSignal;
}

export function notificationPageRange(page: number): [number, number] {
  const start = Math.max(0, page) * NOTIFICATION_PAGE_SIZE;
  return [start, start + NOTIFICATION_PAGE_SIZE - 1];
}

export async function listNotifications(
  userId: string,
  { page, filter = "all", signal }: NotificationPageRequest
): Promise<readonly Notification[]> {
  const [from, to] = notificationPageRange(page);
  let request = getSupabaseClient()
    .from("notifications")
    .select(NOTIFICATION_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false, nullsFirst: false })
    .order("id", { ascending: true });
  if (filter === "unread") request = request.eq("read", false);
  request = request.range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapNotificationRow);
}

/** Counts unread rows server-side for only the current recipient. */
export async function countUnreadNotifications(
  userId: string,
  signal?: AbortSignal
): Promise<number> {
  let request = getSupabaseClient()
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("read", false);
  if (signal) request = request.abortSignal(signal);

  const { count, error } = await request;
  if (error) throw toSupabaseUserError(error);
  return count ?? 0;
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

/** Marks exactly one recipient-owned notification as read; RLS remains final. */
export async function markNotificationRead(notificationId: string, userId: string): Promise<void> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("notifications")
    .update({ read: true })
    .eq("id", notificationId)
    .eq("user_id", userId)
    .select("id")
    .maybeSingle();
  if (error) throw toSupabaseUserError(error);
  if (!data) throw new SupabaseUserError("forbidden", "This notification is unavailable.");
}

/**
 * Marks only the current recipient's unread notifications; it is never
 * replayed offline. The current backend has no atomic cutoff/count RPC, so
 * this intentionally does not download every changed ID to invent a count.
 */
export async function markAllNotificationsRead(userId: string): Promise<void> {
  requireCurrentOnlineMutation();
  const { error } = await getSupabaseClient()
    .from("notifications")
    .update({ read: true })
    .eq("user_id", userId)
    .eq("read", false);
  if (error) throw toSupabaseUserError(error);
}
