export const TASK_STATUSES = [
  "pending_assignment",
  "todo",
  "in_progress",
  "for_review",
  "changes_requested",
  "completed",
  "cancelled"
] as const;

export type TaskStatus = (typeof TASK_STATUSES)[number];

export const TASK_FILTERS = [
  "active",
  "waiting",
  "review",
  "changes_requested",
  "completed",
  "history"
] as const;

export type TaskFilter = (typeof TASK_FILTERS)[number];

export interface Task {
  id: string;
  title: string;
  status: TaskStatus;
  description: string | null;
  priority: string | null;
  dueDate: string | null;
  deadline: string | null;
  percentComplete: number;
  assignedTo: string | null;
  recommendationLeadId: string | null;
  assigneeName: string | null;
  reviewerId: string | null;
  backupReviewerId: string | null;
  teamMemberIds: readonly string[];
  teamMemberNames: readonly string[];
  teamName: string | null;
  dependencyIds: readonly string[];
  acceptanceCriteria: readonly string[];
  definitionOfDone: string | null;
  feedback: string | null;
  /** Canonical UUID relation used for project navigation and project work lists. */
  linkedProjectId: string | null;
  /** Legacy proposal hierarchy value; never use it to construct a project route. */
  projectId: string | null;
  projectTitle: string | null;
  tags: readonly string[];
  subtaskCount: number | null;
  subtaskCompletedCount: number | null;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface TaskSubmission {
  id: string;
  taskId: string;
  version: number;
  note: string;
  status: "pending" | "approved" | "changes_requested" | "unknown";
  submitterId: string;
  submitterName: string;
  submittedAt: string;
  decidedAt: string | null;
  decidedBy: string | null;
  decidedByName: string | null;
  decisionFeedback: string | null;
}

export interface TaskAttachment {
  id: string;
  taskId: string;
  submissionId: string | null;
  fileName: string;
  filePath: string;
  fileSize: number | null;
  mimeType: string | null;
  uploadedBy: string | null;
  uploadedAt: string | null;
}

export interface TaskSubmissionPayload {
  id: string;
  note: string;
  attachments: readonly {
    fileName: string;
    filePath: string;
    fileSize: number;
    mimeType: string;
  }[];
}

export function createTaskSubmissionPayload(
  id: string,
  note: string,
  attachments: TaskSubmissionPayload["attachments"]
): TaskSubmissionPayload {
  const trimmedNote = note.trim();
  if (!trimmedNote) throw new Error("A completion note is required.");
  return { id, note: trimmedNote, attachments };
}

export function isTaskStatus(value: string): value is TaskStatus {
  return (TASK_STATUSES as readonly string[]).includes(value);
}

export function taskStatusLabel(status: TaskStatus): string {
  switch (status) {
    case "pending_assignment":
      return "Waiting for assignment";
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
    case "cancelled":
      return "Cancelled";
  }
}
