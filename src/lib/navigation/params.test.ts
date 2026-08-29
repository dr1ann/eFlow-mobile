import { parseUuidParam } from "@/lib/navigation/params";

describe("route parameter parsing", () => {
  it("accepts one valid UUID", () => {
    expect(parseUuidParam("11111111-1111-4111-8111-111111111111")).toBe(
      "11111111-1111-4111-8111-111111111111"
    );
  });

  it("fails closed for missing, repeated, and malformed values", () => {
    expect(parseUuidParam(undefined)).toBeNull();
    expect(parseUuidParam(["one", "two"])).toBeNull();
    expect(parseUuidParam("not-a-uuid")).toBeNull();
  });
});
