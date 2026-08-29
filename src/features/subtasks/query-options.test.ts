import { subtaskDetailQueryOptions, subtaskProgressQueryOptions } from "@/features/subtasks/query-options";
import { queryKeys } from "@/lib/query/keys";

const subtaskId = "11111111-1111-4111-8111-111111111111";

describe("subtask query options", () => {
  it("uses scoped keys for detail and paginated progress", () => {
    expect(subtaskDetailQueryOptions(subtaskId).queryKey).toEqual(queryKeys.subtasks.detail(subtaskId));
    expect(subtaskProgressQueryOptions(subtaskId, 1).queryKey).toEqual(queryKeys.subtasks.progress(subtaskId, 1));
  });
});
