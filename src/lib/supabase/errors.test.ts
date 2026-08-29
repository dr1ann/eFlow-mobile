import { toSupabaseUserError } from "@/lib/supabase/errors";

describe("Supabase error mapping", () => {
  it.each([
    ["42501", "forbidden"],
    ["P0002", "not_found"],
    ["23505", "duplicate"],
    ["22023", "invalid_state"],
    ["PGRST301", "unauthenticated"],
    ["23514", "validation"]
  ] as const)("maps %s to the safe %s state", (code, kind) => {
    expect(toSupabaseUserError({ code, message: "sensitive database detail" }).kind).toBe(kind);
  });

  it("maps transport failures to an offline message without returning raw details", () => {
    const error = toSupabaseUserError(new TypeError("Network request failed: bearer secret-value"));
    expect(error.kind).toBe("offline");
    expect(error.message).not.toContain("secret-value");
  });

  it("hides unexpected server detail", () => {
    const error = toSupabaseUserError({ code: "XX000", message: "private storage path" });
    expect(error.kind).toBe("server");
    expect(error.message).not.toContain("private storage path");
  });
});
