import { resolveProfile } from "@/contracts/profile";

const baseProfile = {
  id: "8a3b708b-3a46-4ef9-9ce0-211d595240ba",
  full_name: "Taylor User",
  email: "taylor@example.gov",
  org_id: null,
  role: "employee",
  is_active: true
};

describe("resolveProfile", () => {
  it("accepts an active profile with a canonical role", () => {
    expect(resolveProfile(baseProfile)).toMatchObject({
      kind: "authorized",
      profile: { role: "employee" }
    });
  });

  it("rejects inactive, unsupported, and malformed profiles", () => {
    expect(resolveProfile({ ...baseProfile, is_active: false })).toEqual({ kind: "inactive" });
    expect(resolveProfile({ ...baseProfile, role: "executive" })).toEqual({ kind: "unknownRole" });
    expect(resolveProfile({ ...baseProfile, id: "not-a-uuid" })).toEqual({ kind: "malformed" });
  });
});

