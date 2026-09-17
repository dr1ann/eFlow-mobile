import { parsePhase2Capabilities } from "@/lib/phase-2/capabilities";

describe("Phase 2 capability configuration", () => {
  it("uses an explicit allow-list and ignores malformed or unknown values", () => {
    expect([
      ...parsePhase2Capabilities(
        " projectCreate, subtaskCreate, subtaskReorder, unknown, projectCreate, project archive "
      )
    ]).toEqual(["projectCreate", "subtaskCreate", "subtaskReorder"]);
  });

  it("fails closed for absent configuration", () => {
    expect([...parsePhase2Capabilities(undefined)]).toEqual([]);
    expect([...parsePhase2Capabilities("")]).toEqual([]);
  });
});
