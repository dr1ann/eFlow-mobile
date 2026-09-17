import type { Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import {
  EMPTY_SUBTASK_PLANNING_FORM,
  canPlanSubtasks,
  isSubtaskStructureMutable,
  planningCandidatesFromTask,
  reorderedSubtaskIds,
  validateManagedSubtask
} from "@/features/subtasks/subtask-planning";

const ids = {
  task: "11111111-1111-4111-8111-111111111111",
  lead: "22222222-2222-4222-8222-222222222222",
  contributor: "33333333-3333-4333-8333-333333333333",
  other: "44444444-4444-4444-8444-444444444444"
};

function task(overrides: Partial<Task> = {}): Task {
  return {
    id: ids.task,
    title: "Community records update",
    status: "todo",
    description: null,
    priority: "high",
    dueDate: "2026-10-20",
    deadline: "2026-10-20",
    percentComplete: 0,
    assignedTo: ids.lead,
    recommendationLeadId: null,
    assigneeName: "Task Lead",
    reviewerId: null,
    backupReviewerId: null,
    teamMemberIds: [ids.lead, ids.contributor],
    teamMemberNames: ["Task Lead", "Contributor"],
    teamName: "Records team",
    dependencyIds: [],
    acceptanceCriteria: [],
    definitionOfDone: null,
    feedback: null,
    linkedProjectId: null,
    projectId: null,
    projectTitle: null,
    tags: [],
    subtaskCount: null,
    subtaskCompletedCount: null,
    createdAt: null,
    updatedAt: null,
    ...overrides
  };
}

function subtask(overrides: Partial<Subtask> = {}): Subtask {
  return {
    id: ids.other,
    taskId: ids.task,
    title: "Existing step",
    status: "todo",
    percentComplete: 0,
    assignedTo: ids.contributor,
    assignedToIds: [ids.contributor],
    reviewerId: null,
    dueDate: "2026-10-10",
    position: 0,
    isStandalone: false,
    isCompleted: false,
    latestSubmissionId: null,
    source: "manual",
    createdAt: null,
    updatedAt: null,
    ...overrides
  };
}

describe("subtask planning", () => {
  it("derives a de-duplicated candidate list only from the task's authorized participants", () => {
    expect(planningCandidatesFromTask(task())).toEqual([
      { id: ids.lead, label: "Task Lead" },
      { id: ids.contributor, label: "Contributor" }
    ]);
  });

  it("builds a bounded manual subtask payload for an assigned contributor", () => {
    const validation = validateManagedSubtask(
      {
        title: "  Digitize 2025 registers  ",
        assigneeId: ids.contributor,
        dueDate: "2026-10-12",
        executionMode: "standalone"
      },
      task(),
      planningCandidatesFromTask(task()),
      ids.lead,
      [subtask()]
    );

    expect(validation.errors).toEqual({});
    expect(validation.payload).toEqual({
      taskId: ids.task,
      createdBy: ids.lead,
      title: "Digitize 2025 registers",
      assigneeId: ids.contributor,
      dueDate: "2026-10-12",
      position: 1,
      isStandalone: true
    });
  });

  it("rejects malformed, out-of-team, and out-of-range planning input before any write", () => {
    const validation = validateManagedSubtask(
      {
        ...EMPTY_SUBTASK_PLANNING_FORM,
        assigneeId: ids.other,
        dueDate: "2026-10-32"
      },
      task(),
      planningCandidatesFromTask(task()),
      ids.lead,
      []
    );

    expect(validation.payload).toBeNull();
    expect(validation.errors).toEqual({
      title: "A subtask title is required.",
      assigneeId: "Choose an assigned contributor from this task.",
      dueDate: "Use a valid date in YYYY-MM-DD format."
    });

    const afterParentDeadline = validateManagedSubtask(
      { title: "Review", assigneeId: ids.contributor, dueDate: "2026-10-21", executionMode: "sequential" },
      task(),
      planningCandidatesFromTask(task()),
      ids.lead,
      []
    );
    expect(afterParentDeadline.errors.dueDate).toMatch(/cannot be after/i);
  });

  it("does not expose structural controls for locked work or parent states", () => {
    expect(isSubtaskStructureMutable(subtask())).toBe(true);
    expect(isSubtaskStructureMutable(subtask({ status: "in_progress", percentComplete: 10 }))).toBe(false);
    expect(isSubtaskStructureMutable(subtask({ latestSubmissionId: ids.other }))).toBe(false);
    expect(canPlanSubtasks(task({ status: "in_progress" }))).toBe(true);
    expect(canPlanSubtasks(task({ status: "for_review" }))).toBe(false);
  });

  it("creates a complete reordered ID list and rejects impossible moves", () => {
    const first = subtask({ id: ids.lead, position: 0 });
    const second = subtask({ id: ids.contributor, position: 1 });

    expect(reorderedSubtaskIds([first, second], ids.contributor, "up")).toEqual([
      ids.contributor,
      ids.lead
    ]);
    expect(reorderedSubtaskIds([first, second], ids.lead, "up")).toBeNull();
    expect(reorderedSubtaskIds([first, second], ids.other, "down")).toBeNull();
    expect(reorderedSubtaskIds([first, { ...second, status: "in_progress", percentComplete: 10 }], ids.lead, "down")).toBeNull();
  });
});
