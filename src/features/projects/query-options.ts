import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";

import type { ProjectFilter, ProjectOverview } from "@/contracts/projects";
import { queryKeys } from "@/lib/query/keys";

import {
  PROJECT_PAGE_SIZE,
  getProject,
  listProjects,
  projectSearchCacheKey
} from "./api/projects-api";
import { getProjectCompletionReadiness } from "./api/project-workflow-api";

export interface ProjectFeedPage {
  items: readonly ProjectOverview[];
  nextPage: number | null;
}

export function projectsInfiniteQueryOptions(
  userId: string,
  filter: ProjectFilter,
  search: string
) {
  return infiniteQueryOptions({
    queryKey: queryKeys.projects.feed(userId, filter, projectSearchCacheKey(search)),
    initialPageParam: 0,
    queryFn: async ({ pageParam, signal }): Promise<ProjectFeedPage> => {
      const projects = await listProjects({ page: pageParam, filter, search, signal });
      return {
        items: projects,
        nextPage: projects.length === PROJECT_PAGE_SIZE ? pageParam + 1 : null
      };
    },
    getNextPageParam: (lastPage) => lastPage.nextPage,
    staleTime: 30_000
  });
}

export function projectDetailQueryOptions(projectId: string) {
  return queryOptions({
    queryKey: queryKeys.projects.detail(projectId),
    queryFn: ({ signal }) => getProject(projectId, signal),
    staleTime: 15_000
  });
}

export function projectCompletionReadinessQueryOptions(projectId: string) {
  return queryOptions({
    queryKey: queryKeys.projects.completionReadiness(projectId),
    queryFn: () => getProjectCompletionReadiness(projectId),
    staleTime: 10_000,
    retry: false
  });
}
