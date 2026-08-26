import type { RealtimeChannel } from "@supabase/supabase-js";

import { getSupabaseClient } from "@/lib/supabase/client";

type ChangeCallback = () => void;

const activeChannels = new Map<string, RealtimeChannel>();

function subscribe(
  key: string,
  table: "profiles" | "system_config" | "role_permissions" | "user_permission_overrides",
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

