import type { TaskComment } from "@/contracts/discussions";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapTaskCommentRow } from "../mappers";

export const TASK_COMMENT_PAGE_SIZE = 30;

export async function listTaskComments(
  taskId: string,
  page: number,
  signal?: AbortSignal
): Promise<readonly TaskComment[]> {
  const from = Math.max(0, page) * TASK_COMMENT_PAGE_SIZE;
  const to = from + TASK_COMMENT_PAGE_SIZE - 1;
  let request = getSupabaseClient()
    .from("task_comments")
    .select("id,task_id,author_id,author_name,body,created_at,edited_at,deleted_at")
    .eq("task_id", taskId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .range(from, to);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request;
  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapTaskCommentRow);
}

export async function sendTaskComment(input: {
  taskId: string;
  authorId: string;
  authorName: string;
  body: string;
}): Promise<TaskComment> {
  const body = input.body.trim();
  if (!body) throw new Error("Enter a comment before sending.");
  if (body.length > 2_000) throw new Error("Comments must be 2,000 characters or fewer.");
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("task_comments")
    .insert({ task_id: input.taskId, author_id: input.authorId, author_name: input.authorName, body })
    .select("id,task_id,author_id,author_name,body,created_at,edited_at,deleted_at")
    .single();
  if (error) throw toSupabaseUserError(error);
  return mapTaskCommentRow(data);
}
