import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import {
  isSubtaskStatus,
  type Subtask,
  type SubtaskProgressUpdate,
  type SubtaskSubmission,
  type SubtaskSubmissionAttachment
} from "@/contracts/subtasks";

const nullableText = z.string().nullable();
const nullableUuid = z.string().uuid().nullable();

const subtaskRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  title: z.string().trim().min(1),
  status: z.string(),
  percent_complete: z.number().finite().min(0).max(100),
  assigned_to: nullableUuid,
  assigned_to_ids: z.array(z.string().uuid()),
  reviewer_id: nullableUuid,
  due_date: nullableText,
  position: z.number().int().nullable(),
  is_completed: z.boolean().nullable(),
  latest_submission_id: nullableUuid,
  source: nullableText,
  created_at: nullableText,
  updated_at: nullableText
});

const progressRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  subtask_id: z.string().uuid(),
  author_id: z.string().uuid(),
  author_name: z.string(),
  percent_complete: z.number().finite().min(0).max(99),
  blocker_category: nullableText,
  blocker: nullableText,
  next_step: nullableText,
  note: nullableText,
  attachment_path: nullableText,
  attachment_name: nullableText,
  created_at: z.string()
});

const submissionRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  subtask_id: z.string().uuid(),
  version: z.number().int().positive(),
  note: z.string(),
  status: z.string(),
  submitter_id: z.string().uuid(),
  submitter_name: z.string(),
  reviewer_id: z.string().uuid(),
  submitted_at: z.string(),
  decided_at: nullableText,
  decided_by: nullableUuid,
  decided_by_name: nullableText,
  decision_feedback: nullableText
});

const submissionAttachmentRowSchema = z.object({
  id: z.string().uuid(),
  submission_id: z.string().uuid(),
  task_id: z.string().uuid(),
  subtask_id: z.string().uuid(),
  file_name: z.string().trim().min(1),
  file_path: z.string().trim().min(1),
  file_size: z.number().int().nonnegative(),
  mime_type: z.string(),
  uploaded_by: z.string().uuid(),
  created_at: z.string()
});

function submissionStatus(value: string): SubtaskSubmission["status"] {
  if (value === "pending" || value === "approved" || value === "changes_requested") return value;
  return "unknown";
}

export function mapSubtaskRow(row: unknown): Subtask {
  const parsed = subtaskRowSchema.safeParse(row);
  if (!parsed.success) {
    throw new ContractMappingError("subtask");
  }

  const data = parsed.data;
  const status = data.status;
  if (!isSubtaskStatus(status)) throw new ContractMappingError("subtask");

  return {
    id: data.id,
    taskId: data.task_id,
    title: data.title,
    status,
    percentComplete: data.percent_complete,
    assignedTo: data.assigned_to,
    assignedToIds: data.assigned_to_ids,
    reviewerId: data.reviewer_id,
    dueDate: data.due_date,
    position: data.position,
    isCompleted: data.is_completed ?? false,
    latestSubmissionId: data.latest_submission_id,
    source: data.source,
    createdAt: data.created_at,
    updatedAt: data.updated_at
  };
}

export function mapSubtaskProgressRow(row: unknown): SubtaskProgressUpdate {
  const parsed = progressRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("subtask progress");

  const data = parsed.data;
  return {
    id: data.id,
    taskId: data.task_id,
    subtaskId: data.subtask_id,
    authorId: data.author_id,
    authorName: data.author_name,
    percentComplete: data.percent_complete,
    blockerCategory: data.blocker_category,
    blocker: data.blocker,
    nextStep: data.next_step,
    note: data.note,
    attachmentPath: data.attachment_path,
    attachmentName: data.attachment_name,
    createdAt: data.created_at
  };
}

export function mapSubtaskSubmissionRow(row: unknown): SubtaskSubmission {
  const parsed = submissionRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("subtask submission");

  const data = parsed.data;
  return {
    id: data.id,
    taskId: data.task_id,
    subtaskId: data.subtask_id,
    version: data.version,
    note: data.note,
    status: submissionStatus(data.status),
    submitterId: data.submitter_id,
    submitterName: data.submitter_name,
    reviewerId: data.reviewer_id,
    submittedAt: data.submitted_at,
    decidedAt: data.decided_at,
    decidedBy: data.decided_by,
    decidedByName: data.decided_by_name,
    decisionFeedback: data.decision_feedback
  };
}

export function mapSubtaskSubmissionAttachmentRow(row: unknown): SubtaskSubmissionAttachment {
  const parsed = submissionAttachmentRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("subtask submission attachment");

  const data = parsed.data;
  return {
    id: data.id,
    submissionId: data.submission_id,
    taskId: data.task_id,
    subtaskId: data.subtask_id,
    fileName: data.file_name,
    filePath: data.file_path,
    fileSize: data.file_size,
    mimeType: data.mime_type,
    uploadedBy: data.uploaded_by,
    createdAt: data.created_at
  };
}
