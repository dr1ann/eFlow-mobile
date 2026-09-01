import {
  decideTaskReview,
  startTask,
  submitTaskForReview
} from "@/features/tasks/api/task-workflow-api";

const mockRpc = jest.fn();

const taskRow = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Prepare report",
  status: "in_progress",
  description: null,
  priority: null,
  due_date: null,
  deadline: null,
  percent_complete: 10,
  assigned_to: null,
  recommendation_lead_id: null,
  assignee_name: null,
  reviewer_id: null,
  backup_reviewer_id: null,
  team_member_ids: [],
  team_member_names: [],
  team_name: null,
  dependency_ids: [],
  acceptance_criteria: [],
  definition_of_done: null,
  feedback: null,
  project_id: null,
  project_title: null,
  tags: [],
  subtask_count: null,
  subtask_completed_count: null,
  created_at: null,
  updated_at: null
};

jest.mock("@/lib/phase-1/online", () => ({ requireCurrentOnlineMutation: jest.fn() }));
jest.mock("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({ rpc: mockRpc }) }));

describe("task workflow RPC adapter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRpc.mockResolvedValue({ data: taskRow, error: null });
  });

  it("starts only through transition_task_status", async () => {
    await expect(startTask("task-id")).resolves.toMatchObject({ id: taskRow.id });
    expect(mockRpc).toHaveBeenCalledWith("transition_task_status", {
      p_task_id: "task-id",
      p_to_status: "in_progress"
    });
  });

  it("sends immutable submission metadata as one RPC payload", async () => {
    await submitTaskForReview("task-id", {
      id: "submission-id",
      note: "Done",
      attachments: [{ fileName: "proof.pdf", filePath: "task/path", fileSize: 12, mimeType: "application/pdf" }]
    });
    expect(mockRpc).toHaveBeenCalledWith("submit_task_for_review", {
      p_task_id: "task-id",
      p_submission: expect.objectContaining({ id: "submission-id", note: "Done" })
    });
  });

  it("requires feedback before requesting task changes", async () => {
    await expect(decideTaskReview({ taskId: "task-id", approve: false })).rejects.toThrow("Feedback");
    expect(mockRpc).not.toHaveBeenCalled();
  });
});
