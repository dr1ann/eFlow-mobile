import type { PermissionKey } from "@/contracts/permissions";
import type { AuthState } from "@/features/auth/auth-context";

export function canOpenAuthenticatedRoute(state: AuthState): boolean {
  return state.kind === "authorized";
}

export function canOpenPermissionRoute(
  state: AuthState,
  permission: PermissionKey
): boolean {
  return state.kind === "authorized" && state.profile.permissions.has(permission);
}

