import { useMutation, useQueryClient } from "@tanstack/react-query";

import {
  assignManagedSubtask,
  createManagedSubtask,
  reorderManagedSubtasks,
  setManagedSubtaskDueDate,
  setManagedSubtaskExecutionMode,
  type AssignManagedSubtaskInput,
  type SetManagedSubtaskDueDateInput,
  type SetManagedSubtaskExecutionModeInput
} from "@/features/subtasks/api/subtask-planning-api";
import type { CreateManagedSubtaskInput } from "@/features/subtasks/subtask-planning";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";

export function useCreateManagedSubtaskMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: createManagedSubtask,
    retry: false,
    onSuccess: async (_subtask, input: CreateManagedSubtaskInput) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });
}

export function useAssignManagedSubtaskMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: assignManagedSubtask,
    retry: false,
    onSuccess: async (_subtask, input: AssignManagedSubtaskInput) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });
}

export function useSetManagedSubtaskExecutionModeMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: setManagedSubtaskExecutionMode,
    retry: false,
    onSuccess: async (_subtask, input: SetManagedSubtaskExecutionModeInput) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });
}

export function useSetManagedSubtaskDueDateMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: setManagedSubtaskDueDate,
    retry: false,
    onSuccess: async (_subtask, input: SetManagedSubtaskDueDateInput) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });
}

export function useReorderManagedSubtasksMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ taskId, orderedIds }: { taskId: string; orderedIds: readonly string[] }) =>
      reorderManagedSubtasks(taskId, orderedIds),
    retry: false,
    onSuccess: async (_subtasks, input) => {
      await invalidateTaskWorkflow(queryClient, input.taskId);
    }
  });
}
