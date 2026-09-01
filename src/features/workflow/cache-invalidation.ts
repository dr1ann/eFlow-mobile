import type { QueryClient } from "@tanstack/react-query";

import { queryKeys } from "@/lib/query/keys";

/** Refreshes only the workflow surfaces affected by a task-level mutation. */
export async function invalidateTaskWorkflow(
  queryClient: Pick<QueryClient, "invalidateQueries">,
  taskId: string
): Promise<void> {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: queryKeys.tasks.detail(taskId) }),
    queryClient.invalidateQueries({ queryKey: ["tasks", "feed"] }),
    queryClient.invalidateQueries({ queryKey: ["tasks", "leading"] }),
    queryClient.invalidateQueries({ queryKey: queryKeys.subtasks.byTask(taskId) }),
    queryClient.invalidateQueries({ queryKey: ["reviews"] }),
    queryClient.invalidateQueries({ queryKey: ["notifications"] })
  ]);
}

/** Refreshes the subtask timeline and its parent task after a contributor action. */
export async function invalidateSubtaskWorkflow(
  queryClient: Pick<QueryClient, "invalidateQueries">,
  subtaskId: string,
  taskId: string
): Promise<void> {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: queryKeys.subtasks.detail(subtaskId) }),
    queryClient.invalidateQueries({ queryKey: queryKeys.subtasks.progress(subtaskId, 0) }),
    queryClient.invalidateQueries({ queryKey: queryKeys.subtasks.submissions(subtaskId, 0) }),
    queryClient.invalidateQueries({ queryKey: ["subtasks", "mine"] }),
    invalidateTaskWorkflow(queryClient, taskId)
  ]);
}
