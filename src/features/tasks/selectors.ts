import type { Subtask } from "@/contracts/subtasks";
import type { Task, TaskFilter } from "@/contracts/tasks";

export type DeadlineGroup = "overdue" | "today" | "upcoming" | "unscheduled";

export interface TaskDependencyState {
  isReady: boolean;
  blockedByTaskIds: readonly string[];
  missingTaskIds: readonly string[];
}

export interface TaskSubmissionReadiness {
  canSubmit: boolean;
  totalSubtasks: number;
  approvedSubtasks: number;
  outstandingSubtaskIds: readonly string[];
}

function dateOnlyTimestamp(value: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const timestamp = Date.UTC(year, month - 1, day);
  const date = new Date(timestamp);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    return null;
  }
  return timestamp;
}

function taskDeadline(task: Task): string | null {
  return task.deadline ?? task.dueDate;
}

export function isMyTask(task: Task, userId: string): boolean {
  return isTaskLead(task, userId) || task.teamMemberIds.includes(userId);
}

export function effectiveTaskLeadId(task: Task): string | null {
  return task.assignedTo ?? task.recommendationLeadId;
}

export function isTaskLead(task: Task, userId: string): boolean {
  return effectiveTaskLeadId(task) === userId;
}

export function isMySubtask(subtask: Subtask, userId: string): boolean {
  return subtask.assignedTo === userId || subtask.assignedToIds.includes(userId);
}

export function getTaskDependencyState(
  task: Task,
  tasks: readonly Task[]
): TaskDependencyState {
  const tasksById = new Map(tasks.map((candidate) => [candidate.id, candidate]));
  const blockedByTaskIds: string[] = [];
  const missingTaskIds: string[] = [];

  for (const dependencyId of task.dependencyIds) {
    const dependency = tasksById.get(dependencyId);
    if (!dependency) {
      missingTaskIds.push(dependencyId);
    } else if (dependency.status !== "completed") {
      blockedByTaskIds.push(dependencyId);
    }
  }

  return {
    isReady: blockedByTaskIds.length === 0 && missingTaskIds.length === 0,
    blockedByTaskIds,
    missingTaskIds
  };
}

export function taskMatchesFilter(
  task: Task,
  filter: TaskFilter,
  allTasks: readonly Task[]
): boolean {
  switch (filter) {
    case "active":
      return task.status === "todo" || task.status === "in_progress";
    case "waiting":
      return task.status === "pending_assignment" || !getTaskDependencyState(task, allTasks).isReady;
    case "review":
      return task.status === "for_review";
    case "changes_requested":
      return task.status === "changes_requested";
    case "completed":
      return task.status === "completed";
    case "history":
      return task.status === "completed" || task.status === "cancelled";
  }
}

export function sortTasksByDeadline(tasks: readonly Task[]): Task[] {
  return [...tasks].sort((left, right) => {
    const leftTimestamp = taskDeadline(left) ? dateOnlyTimestamp(taskDeadline(left) ?? "") : null;
    const rightTimestamp = taskDeadline(right) ? dateOnlyTimestamp(taskDeadline(right) ?? "") : null;
    const leftSortValue = leftTimestamp ?? Number.POSITIVE_INFINITY;
    const rightSortValue = rightTimestamp ?? Number.POSITIVE_INFINITY;
    if (leftSortValue !== rightSortValue) return leftSortValue - rightSortValue;

    const titleOrder = left.title.localeCompare(right.title);
    if (titleOrder !== 0) return titleOrder;
    return left.id.localeCompare(right.id);
  });
}

export function deadlineGroup(task: Task, now: Date): DeadlineGroup {
  const deadline = taskDeadline(task);
  if (!deadline) return "unscheduled";

  const target = dateOnlyTimestamp(deadline);
  if (target === null) return "unscheduled";
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  if (target < today) return "overdue";
  if (target === today) return "today";
  return "upcoming";
}

export function getTaskSubmissionReadiness(
  subtasks: readonly Subtask[]
): TaskSubmissionReadiness {
  const outstandingSubtaskIds = subtasks
    .filter((subtask) => subtask.status !== "completed" || !subtask.isCompleted)
    .map((subtask) => subtask.id);

  return {
    canSubmit: outstandingSubtaskIds.length === 0,
    totalSubtasks: subtasks.length,
    approvedSubtasks: subtasks.length - outstandingSubtaskIds.length,
    outstandingSubtaskIds
  };
}
