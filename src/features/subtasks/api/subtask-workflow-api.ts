import type { Json } from "@/contracts/database.types";
import type { Subtask } from "@/contracts/subtasks";
import type { SubtaskSubmissionPayload } from "@/features/subtasks/evidence";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapSubtaskRow } from "../mappers";

export interface SubtaskProgressInput {
  subtaskId: string;
  percentComplete: number;
  blockerCategory?: string;
  blocker?: string;
  nextStep?: string;
  note?: string;
  attachmentPath?: string;
  attachmentName?: string;
}

export interface SubtaskReviewDecisionInput {
  subtaskId: string;
  approve: boolean;
  feedback?: string;
}

function optionalText(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function submissionJson(payload: SubtaskSubmissionPayload): Json {
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

/** Saves 0–99% contributor progress through the database workflow RPC. */
export async function saveSubtaskProgress(input: SubtaskProgressInput): Promise<Subtask> {
  if (!Number.isInteger(input.percentComplete) || input.percentComplete < 0 || input.percentComplete >= 100) {
    throw new Error("Progress must be a whole number from 0 to 99.");
  }
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("save_subtask_progress", {
    p_subtask_id: input.subtaskId,
    p_percent_complete: input.percentComplete,
    p_blocker_category: optionalText(input.blockerCategory),
    p_blocker: optionalText(input.blocker),
    p_next_step: optionalText(input.nextStep),
    p_note: optionalText(input.note),
    p_attachment_path: optionalText(input.attachmentPath),
    p_attachment_name: optionalText(input.attachmentName)
  });
  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Submits a fully uploaded subtask attempt exactly once. */
export async function submitSubtaskForReview(
  subtaskId: string,
  submission: SubtaskSubmissionPayload
): Promise<Subtask> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("submit_subtask_for_review", {
    p_subtask_id: subtaskId,
    p_submission: submissionJson(submission)
  });
  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Decides the latest pending subtask attempt. The server rejects self-review. */
export async function decideSubtaskReview(input: SubtaskReviewDecisionInput): Promise<Subtask> {
  if (!input.approve && !input.feedback?.trim()) {
    throw new Error("Feedback is required when requesting changes.");
  }
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("decide_subtask_review", {
    p_subtask_id: input.subtaskId,
    p_approve: input.approve,
    p_feedback: optionalText(input.feedback)
  });
  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}
