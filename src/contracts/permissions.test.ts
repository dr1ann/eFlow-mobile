import { hasPermission, resolveEffectivePermissions } from "@/contracts/permissions";

describe("effective permissions", () => {
  it("uses persisted role rows and applies a user-level deny override", () => {
    const permissions = resolveEffectivePermissions(
      "dept_head",
      [
        { role: "dept_head", permission: "navigation.tasks", allowed: true },
        { role: "dept_head", permission: "tasks.assign", allowed: true }
      ],
      [{ userId: "user", permission: "tasks.assign", allowed: false }]
    );

    expect(hasPermission(permissions, "navigation.tasks")).toBe(true);
    expect(hasPermission(permissions, "tasks.assign")).toBe(false);
    expect(hasPermission(permissions, "users.manage")).toBe(false);
  });

  it("keeps the super-admin UI affordance broad while server authorization remains final", () => {
    const permissions = resolveEffectivePermissions("super_admin", [], []);
    expect(hasPermission(permissions, "database.backup")).toBe(true);
  });
});

