import {
  createSubtaskEvidencePath,
  createSubtaskSubmissionPayload,
  validateEvidenceAssets,
  type EvidenceRules,
  type NativeEvidenceAsset
} from "@/features/subtasks/evidence";
import {
  cleanupTaskEvidence,
  uploadTaskEvidence
} from "@/features/subtasks/evidence-storage";
import { submitSubtaskForReview } from "@/features/subtasks/api/subtask-workflow-api";
import { createWorkflowUuid } from "@/lib/phase-1/ids";
import { mayCleanUpAfterSubmissionFailure } from "@/features/workflow/submission-lifecycle";

export class EvidenceValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EvidenceValidationError";
  }
}

export interface SubmitSubtaskEvidenceInput {
  subtaskId: string;
  note: string;
  assets: readonly NativeEvidenceAsset[];
  rules: EvidenceRules;
}

function validationMessage(input: SubmitSubtaskEvidenceInput): string | null {
  const result = validateEvidenceAssets(input.assets, input.rules);
  if (result.issues.length > 0) return "Review each evidence file's type, size, name, and count before submitting.";
  if (result.accepted.length === 0) return "Select at least one valid evidence file before submitting.";
  return null;
}

/** Uploads a subtask attempt and records it atomically with the review RPC. */
export async function submitSubtaskEvidence(
  input: SubmitSubtaskEvidenceInput
): Promise<void> {
  const note = input.note.trim();
  if (!note) throw new EvidenceValidationError("A completion note is required.");

  const invalid = validationMessage(input);
  if (invalid) throw new EvidenceValidationError(invalid);

  const submissionId = createWorkflowUuid();
  const uploadedPaths: string[] = [];
  try {
    const attachments = [];
    for (const [index, asset] of input.assets.entries()) {
      const path = createSubtaskEvidencePath(
        input.subtaskId,
        submissionId,
        asset,
        index,
        createWorkflowUuid()
      );
      const stored = await uploadTaskEvidence(input.rules, asset, path);
      uploadedPaths.push(stored.filePath);
      attachments.push(stored);
    }
    await submitSubtaskForReview(
      input.subtaskId,
      createSubtaskSubmissionPayload(submissionId, note, attachments)
    );
  } catch (error) {
    if (uploadedPaths.length > 0 && mayCleanUpAfterSubmissionFailure(error)) {
      try {
        await cleanupTaskEvidence(input.rules, uploadedPaths);
      } catch {
        // Preserve the original user-facing error. A cleanup claim is durable,
        // so a failed Storage remove can safely be retried for the same path.
      }
    }
    throw error;
  }
}
