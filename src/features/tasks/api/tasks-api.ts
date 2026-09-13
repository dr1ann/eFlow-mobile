import type { Task, TaskAttachment, TaskSubmission } from "@/contracts/tasks";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapTaskAttachmentRow, mapTaskRow, mapTaskSubmissionRow } from "../mappers";

export const TASK_PAGE_SIZE = 30;

interface PageRequest {
  page: number;
  signal?: AbortSignal;
}

function pageRange(page: number): [number, number] {
  const start = Math.max(0, page) * TASK_PAGE_SIZE;
  return [start, start + TASK_PAGE_SIZE - 1];
}

export function myTaskOwnershipFilter(userId: string): string {
  return `assigned_to.eq.${userId},team_member_ids.cs.{${userId}},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`;
}

export function leadingTaskOwnershipFilter(userId: string): string {
  return `assigned_to.eq.${userId},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`;
}

export async function listMyTasks(
  userId: string,
  { page, signal }: PageRequest
): Promise<readonly Task[]> {
  const [from, to] = pageRange(page);
  const request = getSupabaseClient()
    .from("tasks")
    .select("*")
    .is("deleted_at", null)
    .or(myTaskOwnershipFilter(userId))
    .order("due_date", { ascending: true, nullsFirst: false })
    .order("id", { ascending: true })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskRow);
}

export async function listLeadingTasks(
  userId: string,
  { page, signal }: PageRequest
): Promise<readonly Task[]> {
  const [from, to] = pageRange(page);
  const request = getSupabaseClient()
    .from("tasks")
    .select("*")
    .is("deleted_at", null)
    .or(leadingTaskOwnershipFilter(userId))
    .order("due_date", { ascending: true, nullsFirst: false })
    .order("id", { ascending: true })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskRow);
}

export async function getTask(taskId: string, signal?: AbortSignal): Promise<Task | null> {
  let request = getSupabaseClient()
    .from("tasks")
    .select("*")
    .eq("id", taskId)
    .is("deleted_at", null);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request.maybeSingle();

  if (error) throw toSupabaseUserError(error);
  return data ? mapTaskRow(data) : null;
}

export async function listTaskSubmissions(
  taskId: string,
  { page, signal }: PageRequest
): Promise<readonly TaskSubmission[]> {
  const [from, to] = pageRange(page);
  const request = getSupabaseClient()
    .from("task_submissions")
    .select("*")
    .eq("task_id", taskId)
    .order("version", { ascending: false })
    .range(from, to);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskSubmissionRow);
}

export async function listTaskAttachments(
  taskId: string,
  submissionId: string,
  signal?: AbortSignal
): Promise<readonly TaskAttachment[]> {
  let request = getSupabaseClient()
    .from("task_attachments")
    .select("*")
    .eq("task_id", taskId)
    .order("created_at", { ascending: false })
    .eq("submission_id", submissionId);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskAttachmentRow);
}
