import {
  assignManagedSubtask,
  createManagedSubtask,
  reorderManagedSubtasks,
  setManagedSubtaskDueDate,
  setManagedSubtaskExecutionMode
} from "@/features/subtasks/api/subtask-planning-api";

const mockRpc = jest.fn();
const mockSingle = jest.fn();
const mockSelect = jest.fn(() => ({ single: mockSingle }));
const mockInsert = jest.fn(() => ({ select: mockSelect }));
const mockSecondEq = jest.fn(() => ({ select: mockSelect }));
const mockFirstEq = jest.fn(() => ({ eq: mockSecondEq }));
const mockUpdate = jest.fn(() => ({ eq: mockFirstEq }));
const mockFrom = jest.fn(() => ({ insert: mockInsert, update: mockUpdate }));

const ids = {
  task: "11111111-1111-4111-8111-111111111111",
  subtask: "22222222-2222-4222-8222-222222222222",
  lead: "33333333-3333-4333-8333-333333333333",
  contributor: "44444444-4444-4444-8444-444444444444"
};

const subtaskRow = {
  id: ids.subtask,
  task_id: ids.task,
  title: "Collect evidence",
  status: "todo",
  percent_complete: 0,
  assigned_to: ids.contributor,
  assigned_to_ids: [ids.contributor],
  reviewer_id: null,
  due_date: "2026-10-10",
  position: 0,
  is_standalone: false,
  is_completed: false,
  latest_submission_id: null,
  source: "manual",
  created_at: null,
  updated_at: null
};

jest.mock("@/lib/phase-1/online", () => ({ requireCurrentOnlineMutation: jest.fn() }));
jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({ from: mockFrom, rpc: mockRpc })
}));

describe("subtask planning adapter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSingle.mockResolvedValue({ data: subtaskRow, error: null });
    mockRpc.mockResolvedValue({ data: subtaskRow, error: null });
  });

  it("creates a manually planned subtask with only server-owned workflow fields", async () => {
    await createManagedSubtask({
      taskId: ids.task,
      createdBy: ids.lead,
      title: "Collect evidence",
      assigneeId: ids.contributor,
      dueDate: "2026-10-10",
      position: 2,
      isStandalone: true
    });

    expect(mockFrom).toHaveBeenCalledWith("subtasks");
    expect(mockInsert).toHaveBeenCalledWith(expect.objectContaining({
      task_id: ids.task,
      created_by: ids.lead,
      assigned_to: ids.contributor,
      assigned_to_ids: [ids.contributor],
      source: "manual",
      position: 2,
      is_standalone: true,
      status: "todo",
      percent_complete: 0
    }));
  });

  it("scopes direct structural updates to both the task and subtask IDs", async () => {
    await assignManagedSubtask({ taskId: ids.task, subtaskId: ids.subtask, assigneeId: ids.lead });
    expect(mockUpdate).toHaveBeenCalledWith({ assigned_to: ids.lead, assigned_to_ids: [ids.lead] });
    expect(mockFirstEq).toHaveBeenCalledWith("id", ids.subtask);
    expect(mockSecondEq).toHaveBeenCalledWith("task_id", ids.task);

    await setManagedSubtaskExecutionMode({ taskId: ids.task, subtaskId: ids.subtask, isStandalone: true });
    expect(mockUpdate).toHaveBeenCalledWith({ is_standalone: true });
  });

  it("uses authoritative schedule and reorder RPCs without retrying a mutation", async () => {
    mockRpc
      .mockResolvedValueOnce({ data: subtaskRow, error: null })
      .mockResolvedValueOnce({ data: [subtaskRow], error: null });
    await setManagedSubtaskDueDate({
      taskId: ids.task,
      subtaskId: ids.subtask,
      dueDate: "2026-10-11",
      reason: "  Field schedule changed  "
    });
    expect(mockRpc).toHaveBeenCalledWith("set_subtask_due_date", {
      p_subtask_id: ids.subtask,
      p_due_date: "2026-10-11",
      p_reason: "Field schedule changed"
    });

    await reorderManagedSubtasks(ids.task, [ids.subtask]);
    expect(mockRpc).toHaveBeenCalledWith("reorder_task_subtasks", {
      p_task_id: ids.task,
      p_ordered_ids: [ids.subtask]
    });
  });
});
