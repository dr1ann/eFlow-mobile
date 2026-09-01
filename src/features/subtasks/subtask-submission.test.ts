import { SupabaseUserError } from "@/lib/supabase/errors";
import { submitSubtaskEvidence } from "@/features/subtasks/subtask-submission";

const mockUploadTaskEvidence = jest.fn();
const mockCleanupTaskEvidence = jest.fn();
const mockSubmitSubtaskForReview = jest.fn();
const mockCreateWorkflowUuid = jest.fn();

jest.mock("@/features/subtasks/evidence-storage", () => ({
  uploadTaskEvidence: (...args: unknown[]) => mockUploadTaskEvidence(...args),
  cleanupTaskEvidence: (...args: unknown[]) => mockCleanupTaskEvidence(...args)
}));
jest.mock("@/features/subtasks/api/subtask-workflow-api", () => ({
  submitSubtaskForReview: (...args: unknown[]) => mockSubmitSubtaskForReview(...args)
}));
jest.mock("@/lib/phase-1/ids", () => ({
  createWorkflowUuid: () => mockCreateWorkflowUuid()
}));

const subtaskId = "11111111-1111-4111-8111-111111111111";
const submissionId = "22222222-2222-4222-8222-222222222222";
const suffixId = "33333333-3333-4333-8333-333333333333";
const rules = {
  bucketId: "task-attachments" as const,
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 10,
  recommendedSignedUrlSeconds: 300,
  orphanMinimumAgeHours: 24,
  acceptedMimeTypes: ["application/pdf"]
};
const asset = { uri: "file://proof", displayName: "proof.pdf", mimeType: "application/pdf", size: 12 };

describe("subtask evidence submission", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateWorkflowUuid.mockReturnValueOnce(submissionId).mockReturnValueOnce(suffixId);
    mockUploadTaskEvidence.mockResolvedValue({
      fileName: "proof.pdf",
      filePath: `subtasks/${subtaskId}/${submissionId}/1-33333333333343338333333333333333-proof.pdf`,
      fileSize: 12,
      mimeType: "application/pdf"
    });
    mockSubmitSubtaskForReview.mockResolvedValue(undefined);
  });

  it("uploads a unique candidate path before recording one immutable submission", async () => {
    await submitSubtaskEvidence({ subtaskId, note: "Done", assets: [asset], rules });

    expect(mockUploadTaskEvidence).toHaveBeenCalledWith(
      rules,
      asset,
      `subtasks/${subtaskId}/${submissionId}/1-33333333333343338333333333333333-proof.pdf`
    );
    expect(mockSubmitSubtaskForReview).toHaveBeenCalledWith(subtaskId, expect.objectContaining({
      id: submissionId,
      note: "Done"
    }));
    expect(mockCleanupTaskEvidence).not.toHaveBeenCalled();
  });

  it("claims cleanup after a confirmed server rejection", async () => {
    mockSubmitSubtaskForReview.mockRejectedValue(new SupabaseUserError("validation", "Rejected"));

    await expect(submitSubtaskEvidence({ subtaskId, note: "Done", assets: [asset], rules })).rejects.toThrow("Rejected");
    expect(mockCleanupTaskEvidence).toHaveBeenCalledWith(rules, [
      `subtasks/${subtaskId}/${submissionId}/1-33333333333343338333333333333333-proof.pdf`
    ]);
  });

  it("never cleans up after an ambiguous network failure", async () => {
    mockSubmitSubtaskForReview.mockRejectedValue(new SupabaseUserError("offline", "Offline"));

    await expect(submitSubtaskEvidence({ subtaskId, note: "Done", assets: [asset], rules })).rejects.toThrow("Offline");
    expect(mockCleanupTaskEvidence).not.toHaveBeenCalled();
  });
});
