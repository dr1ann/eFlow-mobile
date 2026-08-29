import type { Subtask } from "@/contracts/subtasks";
import { getTaskSubmissionReadiness } from "@/features/tasks/selectors";

function subtask(overrides: Partial<Subtask> = {}): Subtask {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    taskId: "22222222-2222-4222-8222-222222222222",
    title: "Evidence",
    status: "todo",
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
    updatedAt: null,
    ...overrides
  };
}

describe("parent task submission readiness", () => {
  it("allows a task without subtasks to use the authoritative task submission RPC", () => {
    expect(getTaskSubmissionReadiness([])).toEqual({
      canSubmit: true,
      totalSubtasks: 0,
      approvedSubtasks: 0,
      outstandingSubtaskIds: []
    });
  });

  it("requires every subtask to be both completed and marked completed", () => {
    const first = subtask({ status: "completed", isCompleted: true });
    const second = subtask({
      id: "33333333-3333-4333-8333-333333333333",
      status: "for_review",
      percentComplete: 100
    });
    const third = subtask({
      id: "44444444-4444-4444-8444-444444444444",
      status: "completed",
      isCompleted: false,
      percentComplete: 100
    });

    expect(getTaskSubmissionReadiness([first, second, third])).toEqual({
      canSubmit: false,
      totalSubtasks: 3,
      approvedSubtasks: 1,
      outstandingSubtaskIds: [second.id, third.id]
    });
  });
});
