import { roleLabel, toCanonicalRole } from "@/contracts/roles";

describe("toCanonicalRole", () => {
  it.each([
    ["super_admin", "super_admin"],
    ["superadmin", "super_admin"],
    ["dept_head", "dept_head"],
    ["Department Head", "dept_head"],
    ["department_head", "dept_head"],
    ["assistant-head", "assistant_head"],
    ["employee", "employee"]
  ] as const)("maps %s to %s", (input, expected) => {
    expect(toCanonicalRole(input)).toBe(expected);
  });

  it("denies unknown and desktop-only roles", () => {
    expect(toCanonicalRole("executive")).toBeNull();
    expect(toCanonicalRole("finance")).toBeNull();
    expect(toCanonicalRole(undefined)).toBeNull();
  });

  it("uses clear labels", () => {
    expect(roleLabel("assistant_head")).toBe("Assistant Head");
  });
});

