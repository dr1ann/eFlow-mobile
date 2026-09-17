import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import {
  isTaskStatus,
  type Task,
  type TaskAttachment,
  type TaskSubmission
} from "@/contracts/tasks";

const nullableText = z.string().nullable();
const nullableUuid = z.string().uuid().nullable();

const taskRowSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(1),
  status: z.string(),
  description: nullableText,
  priority: nullableText,
  due_date: nullableText,
  deadline: nullableText,
  percent_complete: z.number().finite().min(0).max(100),
  assigned_to: nullableUuid,
  recommendation_lead_id: nullableUuid,
  assignee_name: nullableText,
  reviewer_id: nullableUuid,
  backup_reviewer_id: nullableUuid,
  team_member_ids: z.array(z.string()).nullish(),
  team_member_names: z.array(z.string()).nullish(),
  team_name: nullableText,
  dependency_ids: z.array(z.string()).nullish(),
  acceptance_criteria: z.unknown(),
  definition_of_done: nullableText,
  feedback: nullableText,
  linked_project_id: nullableUuid,
  project_id: nullableText,
  project_title: nullableText,
  tags: z.array(z.string()).nullish(),
  subtask_count: z.number().int().nonnegative().nullable(),
  subtask_completed_count: z.number().int().nonnegative().nullable(),
  created_at: nullableText,
  updated_at: nullableText
});

const taskSubmissionRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  version: z.number().int().positive(),
  note: z.string(),
  status: z.string(),
  submitter_id: z.string().uuid(),
  submitter_name: z.string(),
  submitted_at: z.string(),
  decided_at: nullableText,
  decided_by: nullableUuid,
  decided_by_name: nullableText,
  decision_feedback: nullableText
});

const taskAttachmentRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  submission_id: nullableUuid,
  file_name: z.string().trim().min(1),
  file_path: z.string().trim().min(1),
  file_size: z.number().int().nonnegative().nullable(),
  mime_type: nullableText,
  uploaded_by: nullableUuid,
  created_at: nullableText
});

function stringList(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function submissionStatus(value: string): TaskSubmission["status"] {
  if (value === "pending" || value === "approved" || value === "changes_requested") return value;
  return "unknown";
}

export function mapTaskRow(row: unknown): Task {
  const parsed = taskRowSchema.safeParse(row);
  if (!parsed.success) {
    throw new ContractMappingError("task");
  }

  const data = parsed.data;
  const status = data.status;
  if (!isTaskStatus(status)) throw new ContractMappingError("task");

  return {
    id: data.id,
    title: data.title,
    status,
    description: data.description,
    priority: data.priority,
    dueDate: data.due_date,
    deadline: data.deadline,
    percentComplete: data.percent_complete,
    assignedTo: data.assigned_to,
    recommendationLeadId: data.recommendation_lead_id,
    assigneeName: data.assignee_name,
    reviewerId: data.reviewer_id,
    backupReviewerId: data.backup_reviewer_id,
    teamMemberIds: data.team_member_ids ?? [],
    teamMemberNames: data.team_member_names ?? [],
    teamName: data.team_name,
    dependencyIds: data.dependency_ids ?? [],
    acceptanceCriteria: stringList(data.acceptance_criteria),
    definitionOfDone: data.definition_of_done,
    feedback: data.feedback,
    linkedProjectId: data.linked_project_id,
    projectId: data.project_id,
    projectTitle: data.project_title,
    tags: data.tags ?? [],
    subtaskCount: data.subtask_count,
    subtaskCompletedCount: data.subtask_completed_count,
    createdAt: data.created_at,
    updatedAt: data.updated_at
  };
}

export function mapTaskSubmissionRow(row: unknown): TaskSubmission {
  const parsed = taskSubmissionRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("task submission");

  const data = parsed.data;
  return {
    id: data.id,
    taskId: data.task_id,
    version: data.version,
    note: data.note,
    status: submissionStatus(data.status),
    submitterId: data.submitter_id,
    submitterName: data.submitter_name,
    submittedAt: data.submitted_at,
    decidedAt: data.decided_at,
    decidedBy: data.decided_by,
    decidedByName: data.decided_by_name,
    decisionFeedback: data.decision_feedback
  };
}

export function mapTaskAttachmentRow(row: unknown): TaskAttachment {
  const parsed = taskAttachmentRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("task attachment");

  const data = parsed.data;
  return {
    id: data.id,
    taskId: data.task_id,
    submissionId: data.submission_id,
    fileName: data.file_name,
    filePath: data.file_path,
    fileSize: data.file_size,
    mimeType: data.mime_type,
    uploadedBy: data.uploaded_by,
    uploadedAt: data.created_at
  };
}
