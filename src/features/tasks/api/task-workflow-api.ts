import type { Json } from "@/contracts/database.types";
import type { Task, TaskSubmissionPayload } from "@/contracts/tasks";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapTaskRow } from "../mappers";

export interface TaskReviewDecisionInput {
  taskId: string;
  approve: boolean;
  feedback?: string;
  auditHash?: string;
}

function submissionJson(payload: TaskSubmissionPayload): Json {
  return {
    id: payload.id,
    note: payload.note,
    attachments: payload.attachments.map((attachment) => ({
      fileName: attachment.fileName,
      filePath: attachment.filePath,
      fileSize: attachment.fileSize,
      mimeType: attachment.mimeType
    }))
  };
}

/** Starts/restarts a task only through the authoritative task state machine. */
export async function startTask(taskId: string): Promise<Task> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("transition_task_status", {
    p_task_id: taskId,
    p_to_status: "in_progress"
  });
  if (error) throw toSupabaseUserError(error);
  return mapTaskRow(data);
}

/** Records a parent evidence submission once; callers must reconcile a timeout by id. */
export async function submitTaskForReview(
  taskId: string,
  submission: TaskSubmissionPayload
): Promise<Task> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("submit_task_for_review", {
    p_task_id: taskId,
    p_submission: submissionJson(submission)
  });
  if (error) throw toSupabaseUserError(error);
  return mapTaskRow(data);
}

/** Reviews a pending parent submission; caller supplies server-required audit data when approving. */
export async function decideTaskReview(input: TaskReviewDecisionInput): Promise<Task> {
  if (!input.approve && !input.feedback?.trim()) {
    throw new Error("Feedback is required when requesting changes.");
  }
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("decide_task_review", {
    p_task_id: input.taskId,
    p_approve: input.approve,
    p_feedback: input.feedback?.trim() || undefined,
    p_audit_hash: input.auditHash?.trim() || undefined
  });
  if (error) throw toSupabaseUserError(error);
  return mapTaskRow(data);
}
