import { z } from "zod";

import type { Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import { taskDeadline } from "@/features/tasks/selectors";

export type SubtaskExecutionMode = "sequential" | "standalone";

export interface SubtaskPlanningCandidate {
  id: string;
  label: string;
}

export interface SubtaskPlanningFormValues {
  title: string;
  assigneeId: string;
  dueDate: string;
  executionMode: SubtaskExecutionMode;
}

export interface CreateManagedSubtaskInput {
  taskId: string;
  createdBy: string;
  title: string;
  assigneeId: string;
  dueDate: string | null;
  position: number;
  isStandalone: boolean;
}

export interface SubtaskPlanningValidation {
  errors: Partial<Record<keyof SubtaskPlanningFormValues, string>>;
  payload: CreateManagedSubtaskInput | null;
}

const calendarDateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const uuidSchema = z.string().uuid();

export const EMPTY_SUBTASK_PLANNING_FORM: SubtaskPlanningFormValues = {
  title: "",
  assigneeId: "",
  dueDate: "",
  executionMode: "sequential"
};

function normalizeTitle(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function isCalendarDate(value: string): boolean {
  if (!calendarDateSchema.safeParse(value).success) return false;
  const [yearPart, monthPart, dayPart] = value.split("-");
  const year = Number(yearPart);
  const month = Number(monthPart);
  const day = Number(dayPart);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/**
 * Uses only people already named on the RLS-authorized task record. This is
 * deliberately not a substitute for the missing permission-scoped people
 * picker required for Department Head task assignment.
 */
export function planningCandidatesFromTask(task: Task): readonly SubtaskPlanningCandidate[] {
  const candidates = new Map<string, SubtaskPlanningCandidate>();

  if (task.assignedTo && uuidSchema.safeParse(task.assignedTo).success) {
    candidates.set(task.assignedTo, {
      id: task.assignedTo,
      label: task.assigneeName?.trim() || "Task Lead"
    });
  }

  task.teamMemberIds.forEach((id, index) => {
    if (!uuidSchema.safeParse(id).success || candidates.has(id)) return;
    const label = task.teamMemberNames[index]?.trim();
    candidates.set(id, { id, label: label || `Assigned contributor ${index + 1}` });
  });

  return [...candidates.values()];
}

export function nextSubtaskPosition(subtasks: readonly Subtask[]): number {
  const positions = subtasks
    .map((subtask) => subtask.position)
    .filter(
      (position): position is number =>
        typeof position === "number" && Number.isInteger(position) && position >= 0
    );
  return positions.length === 0 ? 0 : Math.max(...positions) + 1;
}

/** Planning controls never modify started, submitted, or completed work. */
export function isSubtaskStructureMutable(subtask: Subtask): boolean {
  return (
    subtask.status === "todo" &&
    subtask.percentComplete === 0 &&
    !subtask.isCompleted &&
    subtask.latestSubmissionId === null
  );
}

/** The server remains authoritative; this prevents obviously locked parent states in the UI. */
export function canPlanSubtasks(task: Task): boolean {
  return task.status === "todo" || task.status === "in_progress";
}

function parentDeadlineDate(task: Task): string | null {
  const value = taskDeadline(task);
  if (!value) return null;
  const date = value.slice(0, 10);
  return isCalendarDate(date) ? date : null;
}

export function subtaskDueDateError(task: Task, value: string): string | null {
  if (!isCalendarDate(value)) return "Use a valid date in YYYY-MM-DD format.";
  const parentDeadline = parentDeadlineDate(task);
  if (parentDeadline && value > parentDeadline) {
    return "The subtask date cannot be after the parent task deadline.";
  }
  return null;
}

export function validateManagedSubtask(
  values: SubtaskPlanningFormValues,
  task: Task,
  candidates: readonly SubtaskPlanningCandidate[],
  createdBy: string,
  subtasks: readonly Subtask[]
): SubtaskPlanningValidation {
  const errors: SubtaskPlanningValidation["errors"] = {};
  const title = normalizeTitle(values.title);
  const dueDate = values.dueDate.trim();
  const candidateIds = new Set(candidates.map((candidate) => candidate.id));

  if (!title) errors.title = "A subtask title is required.";
  if (title.length > 160) errors.title = "Subtask titles must be 160 characters or fewer.";

  if (!uuidSchema.safeParse(values.assigneeId).success || !candidateIds.has(values.assigneeId)) {
    errors.assigneeId = "Choose an assigned contributor from this task.";
  }

  if (dueDate) {
    const dueDateError = subtaskDueDateError(task, dueDate);
    if (dueDateError) errors.dueDate = dueDateError;
  }

  if (!canPlanSubtasks(task)) {
    errors.title = "This task is not in a state that allows new subtasks.";
  }
  if (!uuidSchema.safeParse(task.id).success || !uuidSchema.safeParse(createdBy).success) {
    errors.title = "This task cannot be planned until its current access data is refreshed.";
  }

  if (Object.keys(errors).length > 0) return { errors, payload: null };

  return {
    errors,
    payload: {
      taskId: task.id,
      createdBy,
      title,
      assigneeId: values.assigneeId,
      dueDate: dueDate || null,
      position: nextSubtaskPosition(subtasks),
      isStandalone: values.executionMode === "standalone"
    }
  };
}

/** Returns a complete, duplicate-free order for the server-owned reorder RPC. */
export function reorderedSubtaskIds(
  subtasks: readonly Subtask[],
  subtaskId: string,
  direction: "up" | "down"
): readonly string[] | null {
  const ordered = [...subtasks]
    .sort((left, right) => (left.position ?? Number.MAX_SAFE_INTEGER) - (right.position ?? Number.MAX_SAFE_INTEGER) || left.id.localeCompare(right.id));
  const index = ordered.findIndex((subtask) => subtask.id === subtaskId);
  const targetIndex = direction === "up" ? index - 1 : index + 1;
  if (index < 0 || targetIndex < 0 || targetIndex >= ordered.length) return null;
  if (!isSubtaskStructureMutable(ordered[index]!) || !isSubtaskStructureMutable(ordered[targetIndex]!)) {
    return null;
  }

  const current = ordered[index]!;
  ordered[index] = ordered[targetIndex]!;
  ordered[targetIndex] = current;
  return ordered.map((subtask) => subtask.id);
}
