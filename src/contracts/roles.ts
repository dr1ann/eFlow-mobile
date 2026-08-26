export const CANONICAL_ROLES = [
  "super_admin",
  "dept_head",
  "assistant_head",
  "employee"
] as const;

export type CanonicalRole = (typeof CANONICAL_ROLES)[number];

const ROLE_ALIASES: Record<string, CanonicalRole> = {
  super_admin: "super_admin",
  superadmin: "super_admin",
  dept_head: "dept_head",
  depthead: "dept_head",
  department_head: "dept_head",
  departmenthead: "dept_head",
  assistant_head: "assistant_head",
  assistanthead: "assistant_head",
  employee: "employee"
};

function normalizeRoleKey(value: string): string {
  return value.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

export function toCanonicalRole(value: unknown): CanonicalRole | null {
  if (typeof value !== "string") return null;
  return ROLE_ALIASES[normalizeRoleKey(value)] ?? null;
}

export function roleLabel(role: CanonicalRole): string {
  switch (role) {
    case "super_admin":
      return "Super Admin";
    case "dept_head":
      return "Department Head";
    case "assistant_head":
      return "Assistant Head";
    case "employee":
      return "Employee";
  }
}

