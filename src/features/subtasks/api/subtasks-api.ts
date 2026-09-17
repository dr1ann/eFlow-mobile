import type {
  Subtask,
  SubtaskFilter,
  SubtaskProgressUpdate,
  SubtaskStatus,
  SubtaskSubmission,
  SubtaskSubmissionAttachment
} from "@/contracts/subtasks";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import {
  mapSubtaskProgressRow,
  mapSubtaskRow,
  mapSubtaskSubmissionAttachmentRow,
  mapSubtaskSubmissionRow
} from "../mappers";

export const SUBTASK_PAGE_SIZE = 30;

interface PageRequest {
  page: number;
  signal?: AbortSignal;
}

interface SubtaskWorkPageRequest extends PageRequest {
  filter: SubtaskFilter;
}

function pageRange(page: number): [number, number] {
  const start = Math.max(0, page) * SUBTASK_PAGE_SIZE;
  return [start, start + SUBTASK_PAGE_SIZE - 1];
}

export function subtaskStatusesForFilter(filter: SubtaskFilter): readonly SubtaskStatus[] {
  switch (filter) {
    case "active":
      return ["todo", "in_progress"];
    case "review":
      return ["for_review"];
    case "changes_requested":
      return ["changes_requested"];
    case "completed":
    case "history":
      return ["completed"];
  }
}

function applySubtaskStatusFilter<T extends { eq: Function; in: Function }>(
  request: T,
  filter: SubtaskFilter
): T {
  const statuses = subtaskStatusesForFilter(filter);
  return statuses.length === 1
    ? request.eq("status", statuses[0])
    : request.in("status", statuses);
}

export async function listMySubtasks(
  userId: string,
  { page, filter, signal }: SubtaskWorkPageRequest
): Promise<readonly Subtask[]> {
  const [from, to] = pageRange(page);
  const request = applySubtaskStatusFilter(getSupabaseClient()
    .from("subtasks")
    .select("*")
    .or(`assigned_to.eq.${userId},assigned_to_ids.cs.{${userId}}`), filter)
    .order("due_date", { ascending: true, nullsFirst: false })
    .order("position", { ascending: true })
    .order("id", { ascending: true })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskRow);
}

export async function listSubtasksByTask(taskId: string, signal?: AbortSignal): Promise<readonly Subtask[]> {
  const request = getSupabaseClient()
    .from("subtasks")
    .select("*")
    .eq("task_id", taskId)
    .order("position", { ascending: true })
    .order("id", { ascending: true });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskRow);
}

export async function getSubtask(subtaskId: string, signal?: AbortSignal): Promise<Subtask | null> {
  let request = getSupabaseClient().from("subtasks").select("*").eq("id", subtaskId);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request.maybeSingle();

  if (error) throw toSupabaseUserError(error);
  return data ? mapSubtaskRow(data) : null;
}

export async function listSubtaskProgress(
  subtaskId: string,
  { page, signal }: PageRequest
): Promise<readonly SubtaskProgressUpdate[]> {
  const [from, to] = pageRange(page);
  const request = getSupabaseClient()
    .from("subtask_progress_updates")
    .select("*")
    .eq("subtask_id", subtaskId)
    .order("created_at", { ascending: false })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskProgressRow);
}

export async function listSubtaskSubmissions(
  subtaskId: string,
  { page, signal }: PageRequest
): Promise<readonly SubtaskSubmission[]> {
  const [from, to] = pageRange(page);
  const request = getSupabaseClient()
    .from("subtask_submissions")
    .select("*")
    .eq("subtask_id", subtaskId)
    .order("version", { ascending: false })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskSubmissionRow);
}

export async function listSubtaskSubmissionAttachments(
  submissionId: string,
  signal?: AbortSignal
): Promise<readonly SubtaskSubmissionAttachment[]> {
  const request = getSupabaseClient()
    .from("subtask_submission_attachments")
    .select("*")
    .eq("submission_id", submissionId)
    .order("created_at", { ascending: false });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskSubmissionAttachmentRow);
}
