import {
  subtaskDetailQueryOptions,
  subtaskProgressQueryOptions,
  subtaskSubmissionAttachmentsQueryOptions
} from "@/features/subtasks/query-options";
import { queryKeys } from "@/lib/query/keys";

const subtaskId = "11111111-1111-4111-8111-111111111111";
const submissionId = "22222222-2222-4222-8222-222222222222";

describe("subtask query options", () => {
  it("uses scoped keys for detail and paginated progress", () => {
    expect(subtaskDetailQueryOptions(subtaskId).queryKey).toEqual(queryKeys.subtasks.detail(subtaskId));
    expect(subtaskProgressQueryOptions(subtaskId, 1).queryKey).toEqual(queryKeys.subtasks.progress(subtaskId, 1));
    expect(subtaskSubmissionAttachmentsQueryOptions(submissionId).queryKey).toEqual([
      "subtasks",
      "submission-attachments",
      submissionId
    ]);
  });
});
