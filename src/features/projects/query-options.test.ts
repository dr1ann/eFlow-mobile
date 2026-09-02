import {
  projectCompletionReadinessQueryOptions,
  projectDetailQueryOptions,
  projectsInfiniteQueryOptions
} from "@/features/projects/query-options";
import { projectSearchCacheKey } from "@/features/projects/api/projects-api";
import { queryKeys } from "@/lib/query/keys";

describe("project query options", () => {
  it("scopes the project feed to the signed-in user, filter, and redacted search key", () => {
    const search = "Records modernization";
    expect(projectsInfiniteQueryOptions("user-1", "active", search).queryKey).toEqual(
      queryKeys.projects.feed("user-1", "active", projectSearchCacheKey(search))
    );
  });

  it("uses a stable detail key for an RLS-backed project read", () => {
    const projectId = "11111111-1111-4111-8111-111111111111";
    expect(projectDetailQueryOptions(projectId).queryKey).toEqual(queryKeys.projects.detail(projectId));
  });

  it("keeps completion readiness separate from the project summary cache", () => {
    const projectId = "11111111-1111-4111-8111-111111111111";
    expect(projectCompletionReadinessQueryOptions(projectId).queryKey).toEqual([
      "projects",
      "completion-readiness",
      projectId
    ]);
  });
});
