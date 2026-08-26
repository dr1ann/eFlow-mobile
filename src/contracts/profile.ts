import { z } from "zod";

import type { EffectivePermissions } from "@/contracts/permissions";
import { toCanonicalRole, type CanonicalRole } from "@/contracts/roles";

const rawProfileSchema = z.object({
  id: z.string().uuid(),
  full_name: z.string(),
  email: z.string(),
  org_id: z.string().uuid().nullable(),
  role: z.string(),
  is_active: z.boolean()
});

export interface AccessProfile {
  id: string;
  fullName: string;
  email: string;
  organizationId: string | null;
  role: CanonicalRole;
  permissions: EffectivePermissions;
}

export type ProfileResolution =
  | { kind: "authorized"; profile: Omit<AccessProfile, "permissions"> }
  | { kind: "missing" }
  | { kind: "inactive" }
  | { kind: "unknownRole" }
  | { kind: "malformed" };

export function resolveProfile(raw: unknown): ProfileResolution {
  const parsed = rawProfileSchema.safeParse(raw);
  if (!parsed.success) return { kind: "malformed" };
  if (!parsed.data.is_active) return { kind: "inactive" };

  const role = toCanonicalRole(parsed.data.role);
  if (!role) return { kind: "unknownRole" };

  return {
    kind: "authorized",
    profile: {
      id: parsed.data.id,
      fullName: parsed.data.full_name,
      email: parsed.data.email,
      organizationId: parsed.data.org_id,
      role
    }
  };
}

