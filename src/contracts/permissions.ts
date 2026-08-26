import type { CanonicalRole } from "@/contracts/roles";

export const PERMISSION_KEYS = [
  "navigation.projects",
  "navigation.tasks",
  "navigation.reviews",
  "navigation.team_supervision",
  "navigation.team_intelligence",
  "navigation.reports",
  "navigation.announcements",
  "navigation.user_management",
  "navigation.organization",
  "navigation.audit",
  "navigation.system_settings",
  "navigation.data_tools",
  "projects.create",
  "projects.archive",
  "projects.delete",
  "tasks.assign",
  "tasks.verify",
  "reports.export",
  "announcements.publish",
  "users.manage",
  "audit.read",
  "settings.manage",
  "database.backup"
] as const;

export type PermissionKey = (typeof PERMISSION_KEYS)[number];

export interface RolePermission {
  role: string;
  permission: string;
  allowed: boolean;
}

export interface UserPermissionOverride {
  userId: string;
  permission: string;
  allowed: boolean;
}

export type EffectivePermissions = ReadonlySet<string>;

const ALL_PERMISSIONS = new Set<string>(PERMISSION_KEYS);

export function resolveEffectivePermissions(
  role: CanonicalRole,
  rolePermissions: readonly RolePermission[],
  overrides: readonly UserPermissionOverride[]
): EffectivePermissions {
  if (role === "super_admin") return new Set(ALL_PERMISSIONS);

  const result = new Set<string>();

  for (const permission of rolePermissions) {
    if (permission.role !== role) continue;
    if (permission.allowed) result.add(permission.permission);
    else result.delete(permission.permission);
  }

  for (const override of overrides) {
    if (override.allowed) result.add(override.permission);
    else result.delete(override.permission);
  }

  return result;
}

export function hasPermission(
  permissions: EffectivePermissions,
  permission: PermissionKey
): boolean {
  return permissions.has(permission);
}

