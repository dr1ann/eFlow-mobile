export const SUBTASK_STATUSES = [
  "todo",
  "in_progress",
  "for_review",
  "changes_requested",
  "completed"
] as const;

export type SubtaskStatus = (typeof SUBTASK_STATUSES)[number];

export const SUBTASK_FILTERS = [
  "active",
  "review",
  "changes_requested",
  "completed",
  "history"
] as const;

export type SubtaskFilter = (typeof SUBTASK_FILTERS)[number];

export interface Subtask {
  id: string;
  taskId: string;
  title: string;
  status: SubtaskStatus;
  percentComplete: number;
  assignedTo: string | null;
  assignedToIds: readonly string[];
  reviewerId: string | null;
  dueDate: string | null;
  position: number | null;
  isCompleted: boolean;
  latestSubmissionId: string | null;
  source: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface SubtaskProgressUpdate {
  id: string;
  taskId: string;
  subtaskId: string;
  authorId: string;
  authorName: string;
  percentComplete: number;
  blockerCategory: string | null;
  blocker: string | null;
  nextStep: string | null;
  note: string | null;
  attachmentPath: string | null;
  attachmentName: string | null;
  createdAt: string;
}

export interface SubtaskSubmission {
  id: string;
  taskId: string;
  subtaskId: string;
  version: number;
  note: string;
  status: "pending" | "approved" | "changes_requested" | "unknown";
  submitterId: string;
  submitterName: string;
  reviewerId: string;
  submittedAt: string;
  decidedAt: string | null;
  decidedBy: string | null;
  decidedByName: string | null;
  decisionFeedback: string | null;
}

export interface SubtaskSubmissionAttachment {
  id: string;
  submissionId: string;
  taskId: string;
  subtaskId: string;
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
  uploadedBy: string;
  createdAt: string;
}

export function isSubtaskStatus(value: string): value is SubtaskStatus {
  return (SUBTASK_STATUSES as readonly string[]).includes(value);
}

export function subtaskStatusLabel(status: SubtaskStatus): string {
  switch (status) {
    case "todo":
      return "To do";
    case "in_progress":
      return "In progress";
    case "for_review":
      return "In review";
    case "changes_requested":
      return "Changes requested";
    case "completed":
      return "Completed";
  }
}
