import type { DocumentPickerAsset } from "expo-document-picker";
import type { ImagePickerAsset } from "expo-image-picker";
import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";

export interface NativeEvidenceAsset {
  uri: string;
  displayName: string;
  mimeType: string | null;
  size: number | null;
}

export interface EvidencePolicy {
  acceptedMimeTypes: readonly string[];
  maximumBytesPerFile: number;
  maximumFilesPerSubmission: number;
}

export interface EvidenceRules extends EvidencePolicy {
  bucketId: "task-attachments";
  recommendedSignedUrlSeconds: number;
  orphanMinimumAgeHours: number;
}

const evidenceRulesSchema = z.object({
  bucketId: z.literal("task-attachments"),
  maxFileBytes: z.number().int().positive(),
  maxFilesPerSubmission: z.number().int().positive().max(10),
  recommendedSignedUrlSeconds: z.number().int().positive().max(3600),
  orphanMinimumAgeHours: z.number().int().positive(),
  allowedMimeTypes: z.array(z.string().trim().min(1)).min(1)
});

export function parseEvidenceRules(value: unknown): EvidenceRules {
  const parsed = evidenceRulesSchema.safeParse(value);
  if (!parsed.success) throw new ContractMappingError("task evidence rules");

  return {
    bucketId: parsed.data.bucketId,
    maximumBytesPerFile: parsed.data.maxFileBytes,
    maximumFilesPerSubmission: parsed.data.maxFilesPerSubmission,
    recommendedSignedUrlSeconds: parsed.data.recommendedSignedUrlSeconds,
    orphanMinimumAgeHours: parsed.data.orphanMinimumAgeHours,
    acceptedMimeTypes: parsed.data.allowedMimeTypes.map((mime) => mime.toLowerCase())
  };
}

export type EvidenceValidationIssue =
  | { kind: "missing_uri"; displayName: string }
  | { kind: "unknown_mime_type"; displayName: string }
  | { kind: "unsupported_mime_type"; displayName: string }
  | { kind: "unknown_size"; displayName: string }
  | { kind: "too_large"; displayName: string }
  | { kind: "duplicate"; displayName: string }
  | { kind: "too_many_files" };

export interface EvidenceValidationResult {
  accepted: readonly NativeEvidenceAsset[];
  issues: readonly EvidenceValidationIssue[];
}

type PickerAsset = {
  uri: string;
  name?: string | null;
  fileName?: string | null;
  mimeType?: string | null;
  size?: number | null;
  fileSize?: number | null;
};

export function sanitizeEvidenceName(name: string | null | undefined): string {
  const candidate = (name ?? "Evidence").trim().replace(/[\\/:*?"<>|\u0000-\u001F]/g, "_");
  const collapsed = candidate.replace(/\s+/g, " ").replace(/^\.+/, "").slice(0, 120).trim();
  return collapsed.length > 0 ? collapsed : "Evidence";
}

export function normalizeEvidenceAsset(asset: PickerAsset): NativeEvidenceAsset {
  const name = "name" in asset ? asset.name : asset.fileName;
  const size = asset.size ?? asset.fileSize ?? null;

  return {
    uri: asset.uri,
    displayName: sanitizeEvidenceName(name),
    mimeType: asset.mimeType?.trim().toLowerCase() || null,
    size: typeof size === "number" && Number.isFinite(size) && size >= 0 ? size : null
  };
}

export function normalizeDocumentPickerAsset(asset: DocumentPickerAsset): NativeEvidenceAsset {
  return normalizeEvidenceAsset(asset);
}

export function normalizeImagePickerAsset(asset: ImagePickerAsset): NativeEvidenceAsset {
  return normalizeEvidenceAsset(asset);
}

function hasDuplicate(
  candidate: NativeEvidenceAsset,
  accepted: readonly NativeEvidenceAsset[]
): boolean {
  return accepted.some(
    (existing) =>
      existing.displayName.toLocaleLowerCase() === candidate.displayName.toLocaleLowerCase() &&
      existing.mimeType === candidate.mimeType &&
      existing.size === candidate.size
  );
}

export function validateEvidenceAssets(
  assets: readonly NativeEvidenceAsset[],
  policy: EvidencePolicy
): EvidenceValidationResult {
  const accepted: NativeEvidenceAsset[] = [];
  const issues: EvidenceValidationIssue[] = [];

  for (const asset of assets) {
    if (accepted.length >= policy.maximumFilesPerSubmission) {
      issues.push({ kind: "too_many_files" });
      continue;
    }
    if (!asset.uri.trim()) {
      issues.push({ kind: "missing_uri", displayName: asset.displayName });
      continue;
    }
    if (!asset.mimeType) {
      issues.push({ kind: "unknown_mime_type", displayName: asset.displayName });
      continue;
    }
    if (!policy.acceptedMimeTypes.includes(asset.mimeType)) {
      issues.push({ kind: "unsupported_mime_type", displayName: asset.displayName });
      continue;
    }
    if (asset.size === null) {
      issues.push({ kind: "unknown_size", displayName: asset.displayName });
      continue;
    }
    if (asset.size > policy.maximumBytesPerFile) {
      issues.push({ kind: "too_large", displayName: asset.displayName });
      continue;
    }
    if (hasDuplicate(asset, accepted)) {
      issues.push({ kind: "duplicate", displayName: asset.displayName });
      continue;
    }

    accepted.push(asset);
  }

  return { accepted, issues };
}

export interface StoredSubmissionEvidence {
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
}

export interface SubtaskSubmissionPayload {
  id: string;
  note: string;
  attachments: readonly StoredSubmissionEvidence[];
}

export function createSubtaskSubmissionPayload(
  id: string,
  note: string,
  attachments: readonly StoredSubmissionEvidence[]
): SubtaskSubmissionPayload {
  const trimmedNote = note.trim();
  if (!trimmedNote) throw new Error("A completion note is required.");
  if (attachments.length === 0) throw new Error("At least one evidence file is required.");

  return { id, note: trimmedNote, attachments };
}

function assertUuid(value: string, context: string): void {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error(`${context} must be a UUID.`);
  }
}

function uniqueEvidenceName(asset: NativeEvidenceAsset, position: number, suffix: string): string {
  const safeSuffix = suffix.replace(/[^a-zA-Z0-9_]/g, "").slice(0, 32);
  if (!safeSuffix) throw new Error("Evidence paths require a unique suffix.");
  return `${position + 1}-${safeSuffix}-${sanitizeEvidenceName(asset.displayName)}`;
}

/** Builds the exact server-recognized object path for a parent submission. */
export function createTaskEvidencePath(
  taskId: string,
  submissionId: string,
  asset: NativeEvidenceAsset,
  position: number,
  suffix: string
): string {
  assertUuid(taskId, "Task id");
  assertUuid(submissionId, "Submission id");
  return `${taskId}/${submissionId}/${uniqueEvidenceName(asset, position, suffix)}`;
}

/** Builds the exact server-recognized object path for a subtask attempt or progress update. */
export function createSubtaskEvidencePath(
  subtaskId: string,
  attempt: string | "progress",
  asset: NativeEvidenceAsset,
  position: number,
  suffix: string
): string {
  assertUuid(subtaskId, "Subtask id");
  if (attempt !== "progress") assertUuid(attempt, "Submission id");
  return `subtasks/${subtaskId}/${attempt}/${uniqueEvidenceName(asset, position, suffix)}`;
}
