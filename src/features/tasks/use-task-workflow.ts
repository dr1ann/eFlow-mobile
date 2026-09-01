import { useMutation, useQueryClient } from "@tanstack/react-query";

import { startTask } from "@/features/tasks/api/task-workflow-api";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";

export function useStartTaskMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: startTask,
    onSuccess: async (_task, taskId) => {
      await invalidateTaskWorkflow(queryClient, taskId);
    }
  });
}
