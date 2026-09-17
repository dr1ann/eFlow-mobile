import type { Subtask } from "@/contracts/subtasks";
import type { Task, TaskFilter } from "@/contracts/tasks";
import {
  deadlineGroupForDate,
  toDeviceCalendarDate,
  type DeadlineGroup
} from "@/features/tasks/deadlines";

export type { DeadlineGroup } from "@/features/tasks/deadlines";

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

export function taskDeadline(task: Task): string | null {
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
  filter: TaskFilter
): boolean {
  switch (filter) {
    case "active":
      return task.status === "todo" || task.status === "in_progress";
    case "waiting":
      // Dependency readiness needs an authoritative complete-data contract.
      // Do not infer it from one client page of task records.
      return task.status === "pending_assignment";
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
    const leftDate = toDeviceCalendarDate(taskDeadline(left));
    const rightDate = toDeviceCalendarDate(taskDeadline(right));
    const leftSortValue = leftDate?.getTime() ?? Number.POSITIVE_INFINITY;
    const rightSortValue = rightDate?.getTime() ?? Number.POSITIVE_INFINITY;
    if (leftSortValue !== rightSortValue) return leftSortValue - rightSortValue;

    const titleOrder = left.title.localeCompare(right.title);
    if (titleOrder !== 0) return titleOrder;
    return left.id.localeCompare(right.id);
  });
}

export function deadlineGroup(task: Task, now: Date): DeadlineGroup {
  return deadlineGroupForDate(taskDeadline(task), now);
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
