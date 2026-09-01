import type { SubtaskSubmission } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapSubtaskSubmissionRow } from "@/features/subtasks/mappers";
import { mapTaskRow } from "@/features/tasks/mappers";

export const REVIEW_PAGE_SIZE = 30;

function pageRange(page: number): [number, number] {
  const from = Math.max(0, page) * REVIEW_PAGE_SIZE;
  return [from, from + REVIEW_PAGE_SIZE - 1];
}

export async function listPendingTaskReviews(userId: string, page: number, signal?: AbortSignal): Promise<readonly Task[]> {
  const [from, to] = pageRange(page);
  let request = getSupabaseClient()
    .from("tasks")
    .select("*")
    .is("deleted_at", null)
    .eq("status", "for_review")
    .or(`reviewer_id.eq.${userId},backup_reviewer_id.eq.${userId}`)
    .order("updated_at", { ascending: false, nullsFirst: false })
    .range(from, to);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request;
  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskRow);
}

export async function listPendingSubtaskReviews(userId: string, page: number, signal?: AbortSignal): Promise<readonly SubtaskSubmission[]> {
  const [from, to] = pageRange(page);
  let request = getSupabaseClient()
    .from("subtask_submissions")
    .select("*")
    .eq("reviewer_id", userId)
    .eq("status", "pending")
    .order("submitted_at", { ascending: false })
    .range(from, to);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request;
  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskSubmissionRow);
}
