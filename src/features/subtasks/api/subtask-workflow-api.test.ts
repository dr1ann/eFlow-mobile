import {
  decideSubtaskReview,
  saveSubtaskProgress,
  submitSubtaskForReview
} from "@/features/subtasks/api/subtask-workflow-api";

const mockRpc = jest.fn();

const subtaskRow = {
  id: "22222222-2222-4222-8222-222222222222",
  task_id: "11111111-1111-4111-8111-111111111111",
  title: "Collect evidence",
  status: "in_progress",
  percent_complete: 45,
  assigned_to: null,
  assigned_to_ids: [],
  reviewer_id: null,
  due_date: null,
  position: null,
  is_completed: false,
  latest_submission_id: null,
  source: null,
  created_at: null,
  updated_at: null
};

jest.mock("@/lib/phase-1/online", () => ({ requireCurrentOnlineMutation: jest.fn() }));
jest.mock("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({ rpc: mockRpc }) }));

describe("subtask workflow RPC adapter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRpc.mockResolvedValue({ data: subtaskRow, error: null });
  });

  it("keeps progress below 100 and sends empty optional text as undefined", async () => {
    await saveSubtaskProgress({ subtaskId: "subtask-id", percentComplete: 45, note: "  " });
    expect(mockRpc).toHaveBeenCalledWith("save_subtask_progress", expect.objectContaining({
      p_subtask_id: "subtask-id",
      p_percent_complete: 45,
      p_note: undefined
    }));
    await expect(saveSubtaskProgress({ subtaskId: "subtask-id", percentComplete: 100 })).rejects.toThrow("0 to 99");
  });

  it("submits immutable metadata and blocks empty review feedback", async () => {
    await submitSubtaskForReview("subtask-id", {
      id: "submission-id",
      note: "Done",
      attachments: [{ fileName: "proof.pdf", filePath: "path", fileSize: 12, mimeType: "application/pdf" }]
    });
    expect(mockRpc).toHaveBeenCalledWith("submit_subtask_for_review", expect.objectContaining({
      p_subtask_id: "subtask-id"
    }));
    await expect(decideSubtaskReview({ subtaskId: "subtask-id", approve: false })).rejects.toThrow("Feedback");
  });
});
