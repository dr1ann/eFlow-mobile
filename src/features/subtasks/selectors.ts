import type { Subtask, SubtaskFilter } from "@/contracts/subtasks";
import { toDeviceCalendarDate } from "@/features/tasks/deadlines";

export function subtaskMatchesFilter(subtask: Subtask, filter: SubtaskFilter): boolean {
  switch (filter) {
    case "active":
      return subtask.status === "todo" || subtask.status === "in_progress";
    case "review":
      return subtask.status === "for_review";
    case "changes_requested":
      return subtask.status === "changes_requested";
    case "completed":
    case "history":
      return subtask.status === "completed";
  }
}

export function sortSubtasksByDeadline(subtasks: readonly Subtask[]): Subtask[] {
  return [...subtasks].sort((left, right) => {
    const leftDueDate = toDeviceCalendarDate(left.dueDate)?.getTime() ?? Number.POSITIVE_INFINITY;
    const rightDueDate = toDeviceCalendarDate(right.dueDate)?.getTime() ?? Number.POSITIVE_INFINITY;
    if (leftDueDate !== rightDueDate) return leftDueDate - rightDueDate;

    const leftPosition = left.position ?? Number.POSITIVE_INFINITY;
    const rightPosition = right.position ?? Number.POSITIVE_INFINITY;
    if (leftPosition !== rightPosition) return leftPosition - rightPosition;

    const titleOrder = left.title.localeCompare(right.title);
    if (titleOrder !== 0) return titleOrder;
    return left.id.localeCompare(right.id);
  });
}
