import type { Subtask, SubtaskFilter, SubtaskStatus } from "@/contracts/subtasks";
import { subtaskMatchesFilter } from "@/features/subtasks/selectors";

function subtask(status: SubtaskStatus): Subtask {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    taskId: "22222222-2222-4222-8222-222222222222",
    title: "Subtask",
    status,
    percentComplete: 0,
    assignedTo: null,
    assignedToIds: [],
    reviewerId: null,
    dueDate: null,
    position: null,
    isCompleted: false,
    latestSubmissionId: null,
    source: null,
    createdAt: null,
    updatedAt: null
  };
}

describe("subtask filters", () => {
  it.each<[SubtaskStatus, SubtaskFilter, boolean]>([
    ["todo", "active", true],
    ["in_progress", "active", true],
    ["for_review", "review", true],
    ["changes_requested", "changes_requested", true],
    ["completed", "completed", true],
    ["completed", "history", true],
    ["for_review", "active", false]
  ])("maps %s through %s", (status, filter, expected) => {
    expect(subtaskMatchesFilter(subtask(status), filter)).toBe(expected);
  });
});
