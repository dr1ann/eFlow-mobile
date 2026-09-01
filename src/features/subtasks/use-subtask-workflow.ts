import { useMutation, useQueryClient } from "@tanstack/react-query";

import {
  saveSubtaskProgress,
  type SubtaskProgressInput
} from "@/features/subtasks/api/subtask-workflow-api";
import { invalidateSubtaskWorkflow } from "@/features/workflow/cache-invalidation";

export function useSaveSubtaskProgressMutation(taskId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: saveSubtaskProgress,
    onSuccess: async (_subtask, input: SubtaskProgressInput) => {
      await invalidateSubtaskWorkflow(queryClient, input.subtaskId, taskId);
    }
  });
}
