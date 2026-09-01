import type { RealtimeChannel } from "@supabase/supabase-js";

import { getSupabaseClient } from "@/lib/supabase/client";

type ChangeCallback = () => void;
type RealtimeTable =
  | "profiles"
  | "system_config"
  | "role_permissions"
  | "user_permission_overrides"
  | "tasks"
  | "subtasks"
  | "subtask_progress_updates"
  | "subtask_submissions"
  | "task_submissions"
  | "notifications"
  | "announcements"
  | "task_comments";

const activeChannels = new Map<string, RealtimeChannel>();

function subscribe(
  key: string,
  table: RealtimeTable,
  filter: string,
  callback: ChangeCallback
): () => void {
  const supabase = getSupabaseClient();
  const existing = activeChannels.get(key);
  if (existing) void supabase.removeChannel(existing);

  const channel = supabase
    .channel(`eflow-mobile:${key}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table, filter },
      callback
    )
    .subscribe();

  activeChannels.set(key, channel);

  return () => {
    if (activeChannels.get(key) !== channel) return;
    activeChannels.delete(key);
    void supabase.removeChannel(channel);
  };
}

/**
 * Subscribes to a narrowly scoped public table only after its publication and
 * allowed/denied Realtime probe have been accepted for mobile.
 */
export function subscribeToScopedTable(
  key: string,
  table: RealtimeTable,
  filter: string,
  callback: ChangeCallback
): () => void {
  return subscribe(key, table, filter, callback);
}

export function subscribeToPhase1TaskWorkflow(
  taskId: string,
  callback: ChangeCallback
): () => void {
  const unsubscribe = [
    subscribe(`phase1-task:${taskId}`, "tasks", `id=eq.${taskId}`, callback),
    subscribe(`phase1-subtasks:${taskId}`, "subtasks", `task_id=eq.${taskId}`, callback),
    subscribe(`phase1-subtask-progress:${taskId}`, "subtask_progress_updates", `task_id=eq.${taskId}`, callback),
    subscribe(`phase1-subtask-submissions:${taskId}`, "subtask_submissions", `task_id=eq.${taskId}`, callback),
    subscribe(`phase1-task-submissions:${taskId}`, "task_submissions", `task_id=eq.${taskId}`, callback),
    subscribe(`phase1-comments:${taskId}`, "task_comments", `task_id=eq.${taskId}`, callback)
  ];

  return () => {
    for (const stop of unsubscribe) stop();
  };
}

export function subscribeToCurrentProfile(
  userId: string,
  callback: ChangeCallback
): () => void {
  return subscribe(`profile:${userId}`, "profiles", `id=eq.${userId}`, callback);
}

export function subscribeToRolePermissions(
  role: string,
  callback: ChangeCallback
): () => void {
  return subscribe(`role-permissions:${role}`, "role_permissions", `role=eq.${role}`, callback);
}

export function subscribeToUserPermissionOverrides(
  userId: string,
  callback: ChangeCallback
): () => void {
  return subscribe(
    `permission-overrides:${userId}`,
    "user_permission_overrides",
    `user_id=eq.${userId}`,
    callback
  );
}

export function subscribeToGatewayEndpoint(callback: ChangeCallback): () => void {
  return subscribe("gateway-endpoint", "system_config", "key=eq.ai_endpoint", callback);
}

export function clearRealtimeChannels(): void {
  const supabase = getSupabaseClient();
  for (const channel of activeChannels.values()) {
    void supabase.removeChannel(channel);
  }
  activeChannels.clear();
}

export function activeRealtimeChannelCount(): number {
  return activeChannels.size;
}
