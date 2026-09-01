import {
  claimAndRemoveTaskEvidence,
  createTaskEvidenceSignedUrl,
  getTaskEvidenceRules,
  readEvidenceUri,
  uploadTaskEvidence
} from "@/features/subtasks/evidence-storage";

const mockRpc = jest.fn();
const mockUpload = jest.fn();
const mockRemove = jest.fn();
const mockCreateSignedUrl = jest.fn();

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({
    rpc: mockRpc,
    storage: {
      from: () => ({ upload: mockUpload, remove: mockRemove, createSignedUrl: mockCreateSignedUrl })
    }
  })
}));

jest.mock("expo/fetch", () => ({
  fetch: jest.fn()
}));

const rules = {
  bucketId: "task-attachments" as const,
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 10,
  recommendedSignedUrlSeconds: 300,
  orphanMinimumAgeHours: 24,
  acceptedMimeTypes: ["application/pdf"]
};

describe("private evidence storage", () => {
  beforeEach(() => jest.clearAllMocks());

  it("reads the server evidence rules through the generated RPC", async () => {
    mockRpc.mockResolvedValue({ data: {
      bucketId: "task-attachments",
      maxFileBytes: 100,
      maxFilesPerSubmission: 10,
      recommendedSignedUrlSeconds: 300,
      orphanMinimumAgeHours: 24,
      allowedMimeTypes: ["application/pdf"]
    }, error: null });

    await expect(getTaskEvidenceRules()).resolves.toEqual(rules);
    expect(mockRpc).toHaveBeenCalledWith("get_task_evidence_rules");
  });

  it("claims cleanup before removing a candidate object", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    mockRemove.mockResolvedValue({ error: null });

    await expect(claimAndRemoveTaskEvidence(rules, "subtasks/path")).resolves.toBe("removed");
    expect(mockRpc).toHaveBeenCalledWith("claim_task_evidence_cleanup", {
      p_bucket_id: "task-attachments",
      p_object_name: "subtasks/path"
    });
    expect(mockRemove).toHaveBeenCalledWith(["subtasks/path"]);
    expect(mockRpc.mock.invocationCallOrder[0]!).toBeLessThan(mockRemove.mock.invocationCallOrder[0]!);
  });

  it("does not remove a missing path and creates signed URLs only through private Storage", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    mockCreateSignedUrl.mockResolvedValue({ data: { signedUrl: "https://example.test/signed" }, error: null });

    await expect(claimAndRemoveTaskEvidence(rules, "missing")).resolves.toBe("missing");
    expect(mockRemove).not.toHaveBeenCalled();
    await expect(createTaskEvidenceSignedUrl(rules, "path")).resolves.toBe("https://example.test/signed");
    expect(mockCreateSignedUrl).toHaveBeenCalledWith("path", 300);
  });

  it("does not upload when the selected metadata is incomplete", async () => {
    await expect(uploadTaskEvidence(rules, {
      uri: "file://report",
      displayName: "report.pdf",
      mimeType: null,
      size: null
    }, "path")).rejects.toThrow("type and size");
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("reads and decodes base64 data URIs directly into ArrayBuffer", async () => {
    const dataUri = "data:application/pdf;base64,JVBERi0xLjQKJcOkw7zDtsOfCjEgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBSCj4+CmVuZG9iag==";
    const buffer = await readEvidenceUri(dataUri);
    expect(buffer.byteLength).toBe(67);
  });
});
