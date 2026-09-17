import type { Subtask } from "@/contracts/subtasks";
import type { Task, TaskFilter, TaskStatus } from "@/contracts/tasks";
import {
  deadlineGroup,
  effectiveTaskLeadId,
  getTaskDependencyState,
  isMySubtask,
  isMyTask,
  isTaskLead,
  sortTasksByDeadline,
  taskMatchesFilter
} from "@/features/tasks/selectors";

const ids = {
  employee: "11111111-1111-4111-8111-111111111111",
  other: "22222222-2222-4222-8222-222222222222",
  task: "33333333-3333-4333-8333-333333333333"
};

function task(overrides: Partial<Task> = {}): Task {
  return {
    id: ids.task,
    title: "Task",
    status: "todo",
    description: null,
    priority: null,
    dueDate: null,
    deadline: null,
    percentComplete: 0,
    assignedTo: ids.employee,
    recommendationLeadId: null,
    assigneeName: null,
    reviewerId: null,
    backupReviewerId: null,
    teamMemberIds: [],
    teamMemberNames: [],
    teamName: null,
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
    id: "44444444-4444-4444-8444-444444444444",
    taskId: ids.task,
    title: "Subtask",
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

describe("task selectors", () => {
  it("uses the server's assigned-lead-first precedence for my work", () => {
    expect(isMyTask(task(), ids.employee)).toBe(true);
    expect(isTaskLead(task(), ids.employee)).toBe(true);
    expect(isMyTask(task({ assignedTo: null, teamMemberIds: [ids.employee] }), ids.employee)).toBe(true);
    expect(isTaskLead(task({ assignedTo: null, teamMemberIds: [ids.employee] }), ids.employee)).toBe(false);
    expect(isMySubtask(subtask({ assignedToIds: [ids.employee] }), ids.employee)).toBe(true);
  });

  it("uses the persisted recommendation only as an unassigned-task fallback", () => {
    const fallback = task({ assignedTo: null, recommendationLeadId: ids.employee });
    const reassigned = task({ assignedTo: ids.other, recommendationLeadId: ids.employee });

    expect(effectiveTaskLeadId(fallback)).toBe(ids.employee);
    expect(isTaskLead(fallback, ids.employee)).toBe(true);
    expect(isMyTask(fallback, ids.employee)).toBe(true);
    expect(effectiveTaskLeadId(reassigned)).toBe(ids.other);
    expect(isTaskLead(reassigned, ids.employee)).toBe(false);
  });

  it("reports unresolved dependencies without classifying a partial page as waiting", () => {
    const dependencyId = "55555555-5555-4555-8555-555555555555";
    const dependent = task({ dependencyIds: [dependencyId] });

    expect(getTaskDependencyState(dependent, [dependent, task({ id: dependencyId, status: "in_progress" })])).toEqual({
      isReady: false,
      blockedByTaskIds: [dependencyId],
      missingTaskIds: []
    });
    expect(getTaskDependencyState(dependent, [dependent])).toEqual({
      isReady: false,
      blockedByTaskIds: [],
      missingTaskIds: [dependencyId]
    });
    expect(taskMatchesFilter(dependent, "waiting")).toBe(false);
    expect(taskMatchesFilter(task({ status: "pending_assignment" }), "waiting")).toBe(true);
  });

  it.each<[TaskStatus, TaskFilter, boolean]>([
    ["pending_assignment", "waiting", true],
    ["todo", "active", true],
    ["in_progress", "active", true],
    ["for_review", "review", true],
    ["changes_requested", "changes_requested", true],
    ["completed", "completed", true],
    ["cancelled", "history", true],
    ["for_review", "active", false]
  ])("filters %s against %s deterministically", (status, filter, expected) => {
    expect(taskMatchesFilter(task({ status }), filter)).toBe(expected);
  });

  it("sorts valid deadlines first and uses a stable title/id tie break", () => {
    const sorted = sortTasksByDeadline([
      task({ id: "00000000-0000-4000-8000-000000000003", title: "Zulu" }),
      task({ id: "00000000-0000-4000-8000-000000000002", title: "Bravo", dueDate: "2026-09-02" }),
      task({ id: "00000000-0000-4000-8000-000000000001", title: "Alpha", dueDate: "2026-09-02" }),
      task({ id: "00000000-0000-4000-8000-000000000004", title: "Late", deadline: "2026-08-30" })
    ]);

    expect(sorted.map((item) => item.title)).toEqual(["Late", "Alpha", "Bravo", "Zulu"]);
  });

  it("classifies deadlines without treating malformed dates as actionable", () => {
    const now = new Date(2026, 7, 26, 10, 0, 0);
    expect(deadlineGroup(task({ dueDate: "2026-08-25" }), now)).toBe("overdue");
    expect(deadlineGroup(task({ dueDate: "2026-08-26" }), now)).toBe("today");
    expect(deadlineGroup(task({ dueDate: "2026-08-27" }), now)).toBe("upcoming");
    expect(deadlineGroup(task({ dueDate: "not-a-date" }), now)).toBe("unscheduled");
  });
});
