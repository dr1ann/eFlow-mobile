import {
  isProjectPriority,
  projectPriorityLabel,
  projectStatusLabel,
  toProjectStatus
} from "@/contracts/projects";

describe("project contract", () => {
  it("uses the deployed project status vocabulary and maps the known legacy read alias", () => {
    expect(toProjectStatus("planning")).toBe("planning");
    expect(toProjectStatus("on_hold")).toBe("on_hold");
    expect(toProjectStatus("in_progress")).toBe("active");
    expect(toProjectStatus("not_started")).toBeNull();
  });

  it("keeps priority validation and presentation deterministic", () => {
    expect(isProjectPriority("high")).toBe(true);
    expect(isProjectPriority("urgent")).toBe(false);
    expect(projectStatusLabel("on_hold")).toBe("On hold");
    expect(projectPriorityLabel("medium")).toBe("Medium");
  });
});
