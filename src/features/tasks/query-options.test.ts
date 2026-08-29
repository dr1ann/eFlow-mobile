import {
  myTasksInfiniteQueryOptions,
  taskAttachmentsQueryOptions,
  taskDetailQueryOptions,
  taskSubmissionsQueryOptions
} from "@/features/tasks/query-options";
import { queryKeys } from "@/lib/query/keys";

const taskId = "11111111-1111-4111-8111-111111111111";

describe("task query options", () => {
  it("uses scoped, stable cache keys for detail and private evidence metadata", () => {
    expect(taskDetailQueryOptions(taskId).queryKey).toEqual(queryKeys.tasks.detail(taskId));
    expect(taskSubmissionsQueryOptions(taskId, 2).queryKey).toEqual(queryKeys.tasks.submissions(taskId, 2));
    expect(taskAttachmentsQueryOptions(taskId, null).queryKey).toEqual(queryKeys.tasks.attachments(taskId, null));
  });

  it("uses a user-and-filter scoped key for the paged work feed", () => {
    expect(myTasksInfiniteQueryOptions("user-1", "active").queryKey).toEqual(
      queryKeys.tasks.feed("user-1", "active")
    );
  });
});
