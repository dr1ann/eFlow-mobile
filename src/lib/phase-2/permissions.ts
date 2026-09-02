import type { PermissionKey } from "@/contracts/permissions";
import type { AccessProfile } from "@/contracts/profile";
import type { Phase2Capability } from "@/lib/phase-2/capabilities";

/**
 * Phase 2 operational mutations are intentionally narrower than the broad
 * client permission resolver. Super Admin remains an oversight/read-only role
 * for operational projects, and Assistant Head stays fail-closed until its
 * mobile scope is confirmed with an allowed and denied backend probe.
 */
export function canUsePhase2OperationalCapability(
  profile: AccessProfile,
  permission: PermissionKey,
  capability: Phase2Capability,
  isCapabilityEnabled: (candidate: Phase2Capability) => boolean
): boolean {
  return (
    profile.role === "dept_head" &&
    profile.permissions.has(permission) &&
    isCapabilityEnabled(capability)
  );
}

export function phase2OperationalUnavailableMessage(profile: AccessProfile): string {
  if (profile.role === "super_admin") {
    return "Super Admin project access is read-only. Ask the responsible department to make this change.";
  }

  if (profile.role === "assistant_head") {
    return "Assistant Head mobile management is unavailable until its exact server scope is verified.";
  }

  if (profile.role !== "dept_head") {
    return "Only an authorized Department Head can make this mobile project change.";
  }

  return "This mobile action is unavailable until its deployed permission checks are verified.";
}
