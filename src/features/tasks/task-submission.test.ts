import { submitTaskEvidence } from "@/features/tasks/task-submission";

const mockUploadTaskEvidence = jest.fn();
const mockCleanupTaskEvidence = jest.fn();
const mockSubmitTaskForReview = jest.fn();
const mockCreateWorkflowUuid = jest.fn();

jest.mock("@/features/subtasks/evidence-storage", () => ({
  uploadTaskEvidence: (...args: unknown[]) => mockUploadTaskEvidence(...args),
  cleanupTaskEvidence: (...args: unknown[]) => mockCleanupTaskEvidence(...args)
}));
jest.mock("@/features/tasks/api/task-workflow-api", () => ({
  submitTaskForReview: (...args: unknown[]) => mockSubmitTaskForReview(...args)
}));
jest.mock("@/lib/phase-1/ids", () => ({
  createWorkflowUuid: () => mockCreateWorkflowUuid()
}));

const taskId = "11111111-1111-4111-8111-111111111111";
const submissionId = "22222222-2222-4222-8222-222222222222";
const rules = {
  bucketId: "task-attachments" as const,
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 10,
  recommendedSignedUrlSeconds: 300,
  orphanMinimumAgeHours: 24,
  acceptedMimeTypes: ["application/pdf"]
};
const asset = { uri: "file://proof", displayName: "proof.pdf", mimeType: "application/pdf", size: 12 };

describe("task evidence submission", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateWorkflowUuid.mockReturnValue(submissionId);
    mockSubmitTaskForReview.mockResolvedValue(undefined);
  });

  it("rejects a blank completion note before uploading or creating an orphan", async () => {
    await expect(submitTaskEvidence({ taskId, note: "  ", assets: [asset], rules }))
      .rejects.toThrow("completion note");

    expect(mockUploadTaskEvidence).not.toHaveBeenCalled();
    expect(mockCleanupTaskEvidence).not.toHaveBeenCalled();
    expect(mockSubmitTaskForReview).not.toHaveBeenCalled();
  });

  it("allows a parent submission with no optional evidence after validating its note", async () => {
    await submitTaskEvidence({ taskId, note: "  Parent report is complete.  ", assets: [], rules });

    expect(mockUploadTaskEvidence).not.toHaveBeenCalled();
    expect(mockSubmitTaskForReview).toHaveBeenCalledWith(taskId, {
      id: submissionId,
      note: "Parent report is complete.",
      attachments: []
    });
  });
});
