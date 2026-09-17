import type { Subtask, SubtaskFilter, SubtaskStatus } from "@/contracts/subtasks";
import { sortSubtasksByDeadline, subtaskMatchesFilter } from "@/features/subtasks/selectors";

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

  it("sorts assigned subtasks with a stable due-date, position, title, and ID order", () => {
    const sorted = sortSubtasksByDeadline([
      { ...subtask("todo"), id: "33333333-3333-4333-8333-333333333333", title: "Zulu", dueDate: null, position: null },
      { ...subtask("todo"), id: "22222222-2222-4222-8222-222222222222", title: "Bravo", dueDate: "2026-09-16", position: 2 },
      { ...subtask("todo"), id: "11111111-1111-4111-8111-111111111111", title: "Alpha", dueDate: "2026-09-16", position: 2 },
      { ...subtask("todo"), id: "44444444-4444-4444-8444-444444444444", title: "Earlier", dueDate: "2026-09-15", position: 1 }
    ]);

    expect(sorted.map((item) => item.title)).toEqual(["Earlier", "Alpha", "Bravo", "Zulu"]);
  });
});
