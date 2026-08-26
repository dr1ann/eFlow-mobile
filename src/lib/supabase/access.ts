import type { PostgrestError } from "@supabase/supabase-js";

import {
  resolveEffectivePermissions,
  type RolePermission,
  type UserPermissionOverride
} from "@/contracts/permissions";
import {
  resolveProfile,
  type AccessProfile,
  type ProfileResolution
} from "@/contracts/profile";
import { getSupabaseClient } from "@/lib/supabase/client";

export type AccessResolution =
  | { kind: "authorized"; profile: AccessProfile }
  | Exclude<ProfileResolution, { kind: "authorized" }>;

export class SupabaseContractError extends Error {
  constructor(
    message: string,
    readonly cause: PostgrestError
  ) {
    super(message);
    this.name = "SupabaseContractError";
  }
}

function toRolePermission(row: {
  role: string;
  permission: string;
  allowed: boolean;
}): RolePermission {
  return { role: row.role, permission: row.permission, allowed: row.allowed };
}

function toUserPermissionOverride(row: {
  user_id: string;
  permission: string;
  allowed: boolean;
}): UserPermissionOverride {
  return { userId: row.user_id, permission: row.permission, allowed: row.allowed };
}

export async function loadAccessProfile(userId: string): Promise<AccessResolution> {
  const supabase = getSupabaseClient();
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, full_name, email, org_id, role, is_active")
    .eq("id", userId)
    .maybeSingle();

  if (profileError) {
    throw new SupabaseContractError("The signed-in profile could not be loaded.", profileError);
  }
  if (!profile) return { kind: "missing" };

  const resolution = resolveProfile(profile);
  if (resolution.kind !== "authorized") return resolution;

  const [roleResult, overrideResult] = await Promise.all([
    supabase.from("role_permissions").select("role, permission, allowed"),
    supabase
      .from("user_permission_overrides")
      .select("user_id, permission, allowed")
      .eq("user_id", userId)
  ]);

  if (roleResult.error) {
    throw new SupabaseContractError("Effective permissions could not be loaded.", roleResult.error);
  }
  if (overrideResult.error) {
    throw new SupabaseContractError("Personal permission overrides could not be loaded.", overrideResult.error);
  }

  return {
    kind: "authorized",
    profile: {
      ...resolution.profile,
      permissions: resolveEffectivePermissions(
        resolution.profile.role,
        (roleResult.data ?? []).map(toRolePermission),
        (overrideResult.data ?? []).map(toUserPermissionOverride)
      )
    }
  };
}

