import { createWorkflowUuid, formatUuidV4 } from "./ids";

const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

describe("createWorkflowUuid", () => {
  it("returns distinct RFC 4122 version-4 UUIDs", () => {
    const first = createWorkflowUuid();
    const second = createWorkflowUuid();

    expect(first).toMatch(UUID_V4_PATTERN);
    expect(second).toMatch(UUID_V4_PATTERN);
    expect(second).not.toBe(first);
  });
});

describe("formatUuidV4", () => {
  it("sets the required version and variant bits", () => {
    expect(formatUuidV4(new Uint8Array(16))).toBe("00000000-0000-4000-8000-000000000000");
  });

  it("rejects a value with the wrong byte length", () => {
    expect(() => formatUuidV4(new Uint8Array(15))).toThrow("exactly 16 bytes");
  });
});
