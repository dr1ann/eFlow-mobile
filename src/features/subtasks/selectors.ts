import type { Subtask, SubtaskFilter } from "@/contracts/subtasks";

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
