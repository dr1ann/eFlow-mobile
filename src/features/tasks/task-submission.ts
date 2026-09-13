import {
  createTaskEvidencePath,
  validateEvidenceAssets,
  type EvidenceRules,
  type NativeEvidenceAsset
} from "@/features/subtasks/evidence";
import {
  cleanupTaskEvidence,
  uploadTaskEvidence
} from "@/features/subtasks/evidence-storage";
import { submitTaskForReview } from "@/features/tasks/api/task-workflow-api";
import { createTaskSubmissionPayload } from "@/contracts/tasks";
import { createWorkflowUuid } from "@/lib/phase-1/ids";
import { mayCleanUpAfterSubmissionFailure } from "@/features/workflow/submission-lifecycle";

export interface SubmitTaskEvidenceInput {
  taskId: string;
  note: string;
  assets: readonly NativeEvidenceAsset[];
  rules: EvidenceRules;
}

/** Parent evidence is optional, but each selected file must meet server rules. */
export async function submitTaskEvidence(input: SubmitTaskEvidenceInput): Promise<void> {
  const note = input.note.trim();
  if (!note) throw new Error("A completion note is required.");

  const validation = validateEvidenceAssets(input.assets, input.rules);
  if (validation.issues.length > 0) {
    throw new Error("Review each evidence file's type, size, name, and count before submitting.");
  }

  const submissionId = createWorkflowUuid();
  const uploadedPaths: string[] = [];
  try {
    const attachments = [];
    for (const [index, asset] of validation.accepted.entries()) {
      const path = createTaskEvidencePath(
        input.taskId,
        submissionId,
        asset,
        index,
        createWorkflowUuid()
      );
      const stored = await uploadTaskEvidence(input.rules, asset, path);
      uploadedPaths.push(stored.filePath);
      attachments.push(stored);
    }
    await submitTaskForReview(
      input.taskId,
      createTaskSubmissionPayload(submissionId, note, attachments)
    );
  } catch (error) {
    if (uploadedPaths.length > 0 && mayCleanUpAfterSubmissionFailure(error)) {
      try {
        await cleanupTaskEvidence(input.rules, uploadedPaths);
      } catch {
        // Do not mask the original server response or attempt an unsafe delete.
      }
    }
    throw error;
  }
}
