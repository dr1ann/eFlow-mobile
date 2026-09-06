import {
  isPhase3FixtureMode,
  parsePhase3Capabilities
} from "@/lib/phase-3/capabilities";

describe("Phase 3 capability configuration", () => {
  it("uses an explicit allow-list and ignores unknown or duplicate values", () => {
    expect([
      ...parsePhase3Capabilities(
        " notificationSummary, chatRead, unknown, chatRead, proposal import "
      )
    ]).toEqual(["notificationSummary", "chatRead"]);
  });

  it("fails closed for absent configuration and never enables fixtures in production", () => {
    expect([...parsePhase3Capabilities(undefined)]).toEqual([]);
    expect(isPhase3FixtureMode("true", false)).toBe(false);
    expect(isPhase3FixtureMode("false", true)).toBe(false);
    expect(isPhase3FixtureMode("true", true)).toBe(true);
  });
});
