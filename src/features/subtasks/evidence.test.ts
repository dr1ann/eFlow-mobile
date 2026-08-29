import {
  createSubtaskSubmissionPayload,
  normalizeEvidenceAsset,
  sanitizeEvidenceName,
  validateEvidenceAssets
} from "@/features/subtasks/evidence";

const policy = {
  acceptedMimeTypes: ["application/pdf", "image/jpeg"],
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 2
} as const;

describe("evidence normalization and validation", () => {
  it("sanitizes display names without exposing a local path", () => {
    expect(sanitizeEvidenceName("../signed:report?.pdf")).toBe("_signed_report_.pdf");
    expect(normalizeEvidenceAsset({
      uri: "file:///private/cache/report.pdf",
      name: "report.pdf",
      mimeType: "APPLICATION/PDF",
      size: 99
    })).toEqual({
      uri: "file:///private/cache/report.pdf",
      displayName: "report.pdf",
      mimeType: "application/pdf",
      size: 99
    });
  });

  it("rejects unsupported, oversized, unknown, duplicate, and excess files before upload", () => {
    const result = validateEvidenceAssets([
      { uri: "file://one", displayName: "one.pdf", mimeType: "application/pdf", size: 100 },
      { uri: "file://two", displayName: "two.png", mimeType: "image/png", size: 1 },
      { uri: "file://three", displayName: "three.jpg", mimeType: "image/jpeg", size: null },
      { uri: "file://four", displayName: "one.pdf", mimeType: "application/pdf", size: 100 },
      { uri: "file://five", displayName: "five.jpg", mimeType: "image/jpeg", size: 101 },
      { uri: "file://six", displayName: "six.jpg", mimeType: "image/jpeg", size: 1 },
      { uri: "file://seven", displayName: "seven.jpg", mimeType: "image/jpeg", size: 1 }
    ], policy);

    expect(result.accepted).toHaveLength(2);
    expect(result.issues.map((issue) => issue.kind)).toEqual([
      "unsupported_mime_type",
      "unknown_size",
      "duplicate",
      "too_large",
      "too_many_files"
    ]);
  });

  it("requires a non-empty note and evidence metadata for an RPC submission", () => {
    expect(() => createSubtaskSubmissionPayload("attempt-1", " ", [])).toThrow("completion note");
    expect(() => createSubtaskSubmissionPayload("attempt-1", "Done", [])).toThrow("At least one evidence");
    expect(createSubtaskSubmissionPayload("attempt-1", " Done ", [{
      fileName: "report.pdf",
      filePath: "pending-contract/report.pdf",
      fileSize: 12,
      mimeType: "application/pdf"
    }])).toMatchObject({ id: "attempt-1", note: "Done" });
  });
});
