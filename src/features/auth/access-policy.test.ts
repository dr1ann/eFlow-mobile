import { canOpenAuthenticatedRoute, canOpenPermissionRoute } from "@/features/auth/access-policy";
import type { AuthState } from "@/features/auth/auth-context";
import type { Session } from "@supabase/supabase-js";

const session = {
  access_token: "redacted",
  refresh_token: "redacted",
  expires_in: 3600,
  token_type: "bearer",
  user: { id: "user" }
} as Session;

describe("route access policy", () => {
  it("does not allow a signed-out or rejected state through protected routes", () => {
    expect(canOpenAuthenticatedRoute({ kind: "signedOut" })).toBe(false);
    expect(canOpenAuthenticatedRoute({ kind: "rejected", session, message: "Inactive" })).toBe(false);
  });

  it("requires the exact effective permission for a restricted route", () => {
    const state: AuthState = {
      kind: "authorized",
      session,
      profile: {
        id: "user",
        fullName: "User",
        email: "user@example.gov",
        organizationId: null,
        role: "employee",
        permissions: new Set(["navigation.tasks"])
      }
    };

    expect(canOpenAuthenticatedRoute(state)).toBe(true);
    expect(canOpenPermissionRoute(state, "navigation.user_management")).toBe(false);
    expect(canOpenPermissionRoute(state, "navigation.projects")).toBe(false);
    expect(canOpenPermissionRoute(state, "navigation.tasks")).toBe(true);
  });

  it("requires navigation.projects before exposing project routes", () => {
    const state: AuthState = {
      kind: "authorized",
      session,
      profile: {
        id: "user",
        fullName: "Department Head",
        email: "head@example.gov",
        organizationId: null,
        role: "dept_head",
        permissions: new Set(["navigation.projects"])
      }
    };

    expect(canOpenPermissionRoute(state, "navigation.projects")).toBe(true);
    expect(canOpenPermissionRoute(state, "projects.create")).toBe(false);
  });
});
