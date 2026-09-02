import { useMutation, useQueryClient, type QueryClient } from "@tanstack/react-query";

import type { Json } from "@/contracts/database.types";
import {
  archiveCompletedProject,
  completeProject,
  createProjectWithDetails
} from "@/features/projects/api/project-workflow-api";
import { queryKeys } from "@/lib/query/keys";

export async function invalidateProjectWorkflow(
  queryClient: Pick<QueryClient, "invalidateQueries">,
  projectId?: string
): Promise<void> {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: ["projects", "feed"] }),
    ...(projectId
      ? [
          queryClient.invalidateQueries({ queryKey: queryKeys.projects.detail(projectId) }),
          queryClient.invalidateQueries({ queryKey: queryKeys.projects.completionReadiness(projectId) })
        ]
      : []),
    queryClient.invalidateQueries({ queryKey: ["tasks"] }),
    queryClient.invalidateQueries({ queryKey: ["reviews"] }),
    queryClient.invalidateQueries({ queryKey: ["notifications"] })
  ]);
}

export function useCreateProjectMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: Json) => createProjectWithDetails(payload),
    onSuccess: async (project) => {
      await invalidateProjectWorkflow(queryClient, project.id);
    }
  });
}

export function useCompleteProjectMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ projectId, note }: { projectId: string; note: string }) => completeProject(projectId, note),
    onSuccess: async (_result, input) => {
      await invalidateProjectWorkflow(queryClient, input.projectId);
    }
  });
}

export function useArchiveProjectMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ projectId, reason }: { projectId: string; reason: string }) =>
      archiveCompletedProject(projectId, reason),
    onSuccess: async (_result, input) => {
      await invalidateProjectWorkflow(queryClient, input.projectId);
    }
  });
}
