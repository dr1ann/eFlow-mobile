import type { Subtask } from "@/contracts/subtasks";
import type { CreateManagedSubtaskInput } from "@/features/subtasks/subtask-planning";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapSubtaskRow } from "../mappers";

export interface AssignManagedSubtaskInput {
  taskId: string;
  subtaskId: string;
  assigneeId: string;
}

export interface SetManagedSubtaskExecutionModeInput {
  taskId: string;
  subtaskId: string;
  isStandalone: boolean;
}

export interface SetManagedSubtaskDueDateInput {
  taskId: string;
  subtaskId: string;
  dueDate: string;
  reason?: string;
}

/**
 * Creates a manual subtask through the deployed RLS/trigger contract. This
 * action is capability-gated in the UI and never queued or retried by the
 * client; the server remains the authorization and lifecycle boundary.
 */
export async function createManagedSubtask(input: CreateManagedSubtaskInput): Promise<Subtask> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("subtasks")
    .insert({
      task_id: input.taskId,
      title: input.title,
      source: "manual",
      position: input.position,
      created_by: input.createdBy,
      assigned_to: input.assigneeId,
      assigned_to_ids: [input.assigneeId],
      due_date: input.dueDate,
      is_standalone: input.isStandalone,
      status: "todo",
      percent_complete: 0,
      is_completed: false
    })
    .select()
    .single();

  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Reassigns only a not-yet-started subtask through the RLS-enforced row update. */
export async function assignManagedSubtask(input: AssignManagedSubtaskInput): Promise<Subtask> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("subtasks")
    .update({ assigned_to: input.assigneeId, assigned_to_ids: [input.assigneeId] })
    .eq("id", input.subtaskId)
    .eq("task_id", input.taskId)
    .select()
    .single();

  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Changes the sequential/standalone execution rule through the guarded row update. */
export async function setManagedSubtaskExecutionMode(
  input: SetManagedSubtaskExecutionModeInput
): Promise<Subtask> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient()
    .from("subtasks")
    .update({ is_standalone: input.isStandalone })
    .eq("id", input.subtaskId)
    .eq("task_id", input.taskId)
    .select()
    .single();

  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Uses the dedicated deadline RPC so parent-range and audit checks stay server-owned. */
export async function setManagedSubtaskDueDate(
  input: SetManagedSubtaskDueDateInput
): Promise<Subtask> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("set_subtask_due_date", {
    p_subtask_id: input.subtaskId,
    p_due_date: input.dueDate,
    p_reason: input.reason?.trim() || undefined
  });

  if (error) throw toSupabaseUserError(error);
  return mapSubtaskRow(data);
}

/** Sends every current subtask ID exactly once to the server-owned reorder RPC. */
export async function reorderManagedSubtasks(
  taskId: string,
  orderedIds: readonly string[]
): Promise<readonly Subtask[]> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("reorder_task_subtasks", {
    p_task_id: taskId,
    p_ordered_ids: [...orderedIds]
  });

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapSubtaskRow);
}
