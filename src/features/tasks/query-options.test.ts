import {
  leadingTasksInfiniteQueryOptions,
  myTasksInfiniteQueryOptions,
  projectTasksInfiniteQueryOptions,
  taskAttachmentsQueryOptions,
  taskDetailQueryOptions,
  taskSubmissionsQueryOptions
} from "@/features/tasks/query-options";
import { queryKeys } from "@/lib/query/keys";

const taskId = "11111111-1111-4111-8111-111111111111";
const submissionId = "22222222-2222-4222-8222-222222222222";

describe("task query options", () => {
  it("uses scoped, stable cache keys for detail and private evidence metadata", () => {
    expect(taskDetailQueryOptions(taskId).queryKey).toEqual(queryKeys.tasks.detail(taskId));
    expect(taskSubmissionsQueryOptions(taskId, 2).queryKey).toEqual(queryKeys.tasks.submissions(taskId, 2));
    expect(taskAttachmentsQueryOptions(taskId, submissionId).queryKey).toEqual(
      queryKeys.tasks.attachments(taskId, submissionId)
    );
  });

  it("uses a user-and-filter scoped key for the paged work feed", () => {
    expect(myTasksInfiniteQueryOptions("user-1", "active").queryKey).toEqual(
      queryKeys.tasks.feed("user-1", "active")
    );
  });

  it("keeps leading work and project work in separate scoped feeds", () => {
    expect(leadingTasksInfiniteQueryOptions("user-1", "active").queryKey).toEqual(
      queryKeys.tasks.leadingFeed("user-1", "active")
    );
    expect(projectTasksInfiniteQueryOptions(taskId).queryKey).toEqual(
      queryKeys.tasks.byProject(taskId)
    );
  });
});
