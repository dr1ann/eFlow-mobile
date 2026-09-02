import type { AccessProfile } from "@/contracts/profile";
import { canUsePhase2OperationalCapability, phase2OperationalUnavailableMessage } from "@/lib/phase-2/permissions";

function profile(role: AccessProfile["role"], permissions: readonly string[]): AccessProfile {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    fullName: "Test user",
    email: "test@example.com",
    organizationId: "22222222-2222-4222-8222-222222222222",
    role,
    permissions: new Set(permissions)
  };
}

describe("Phase 2 operational permission guard", () => {
  it("requires the Department Head role, exact permission, and enabled capability", () => {
    const departmentHead = profile("dept_head", ["projects.create"]);

    expect(
      canUsePhase2OperationalCapability(
        departmentHead,
        "projects.create",
        "projectCreate",
        (capability) => capability === "projectCreate"
      )
    ).toBe(true);
    expect(
      canUsePhase2OperationalCapability(
        departmentHead,
        "projects.create",
        "projectCreate",
        () => false
      )
    ).toBe(false);
  });

  it("does not let broad Super Admin client permissions create operational access", () => {
    const superAdmin = profile("super_admin", ["projects.create", "projects.archive"]);

    expect(
      canUsePhase2OperationalCapability(
        superAdmin,
        "projects.create",
        "projectCreate",
        () => true
      )
    ).toBe(false);
    expect(phase2OperationalUnavailableMessage(superAdmin)).toMatch(/read-only/i);
  });

  it("fails closed for Assistant Head until the mobile contract is verified", () => {
    const assistantHead = profile("assistant_head", ["projects.create"]);

    expect(
      canUsePhase2OperationalCapability(
        assistantHead,
        "projects.create",
        "projectCreate",
        () => true
      )
    ).toBe(false);
    expect(phase2OperationalUnavailableMessage(assistantHead)).toMatch(/scope is verified/i);
  });
});
