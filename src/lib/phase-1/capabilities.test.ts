import {
  isPhase1FixtureMode,
  parsePhase1Capabilities
} from "@/lib/phase-1/capabilities";

describe("Phase 1 capability configuration", () => {
  it("uses an explicit allow-list and ignores unknown values", () => {
    expect([...parsePhase1Capabilities(" taskTransition, evidenceUpload, not-real, taskTransition ")])
      .toEqual(["taskTransition", "evidenceUpload"]);
  });

  it("keeps fixtures unavailable outside development", () => {
    expect(isPhase1FixtureMode("true", false)).toBe(false);
    expect(isPhase1FixtureMode("false", true)).toBe(false);
    expect(isPhase1FixtureMode("true", true)).toBe(true);
  });
});
