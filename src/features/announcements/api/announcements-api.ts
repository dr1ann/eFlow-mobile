import type { Announcement } from "@/contracts/announcements";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { SupabaseUserError, toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapAnnouncementRow } from "../mappers";

export const ANNOUNCEMENT_PAGE_SIZE = 25;
export const ANNOUNCEMENT_SELECT = "id,title,body,status,audience,published_at,expires_at,created_at,updated_at";

export async function listRecipientAnnouncements(
  userId: string,
  page: number,
  signal?: AbortSignal
): Promise<readonly Announcement[]> {
  const from = Math.max(0, page) * ANNOUNCEMENT_PAGE_SIZE;
  const to = from + ANNOUNCEMENT_PAGE_SIZE - 1;
  let recipients = getSupabaseClient()
    .from("announcement_recipients")
    .select("announcement_id")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(from, to);
  if (signal) recipients = recipients.abortSignal(signal);
  const { data: recipientRows, error: recipientError } = await recipients;
  if (recipientError) throw toSupabaseUserError(recipientError);
  const ids = (recipientRows ?? []).map((row) => row.announcement_id);
  if (ids.length === 0) return [];

  let announcements = getSupabaseClient()
    .from("announcements")
    .select(ANNOUNCEMENT_SELECT)
    .in("id", ids)
    .eq("status", "published")
    .order("published_at", { ascending: false, nullsFirst: false });
  if (signal) announcements = announcements.abortSignal(signal);
  const { data, error } = await announcements;
  if (error) throw toSupabaseUserError(error);

  const now = Date.now();
  return (data ?? [])
    .map(mapAnnouncementRow)
    .filter((announcement) => announcement.expiresAt === null || Date.parse(announcement.expiresAt) > now);
}

export async function markAnnouncementRead(announcementId: string, userId: string): Promise<void> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("announcement_recipients")
    .update({ read_at: new Date().toISOString() })
    .eq("announcement_id", announcementId)
    .eq("user_id", userId)
    .select("announcement_id")
    .maybeSingle();
  if (error) throw toSupabaseUserError(error);
  if (!data) throw new SupabaseUserError("forbidden", "This announcement is unavailable.");
}
