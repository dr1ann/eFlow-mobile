import {
  EMPTY_PROJECT_CREATE_FORM,
  validateProjectCreate
} from "@/features/projects/project-management";

describe("project creation validation", () => {
  it("builds a narrow self-owned planning-project RPC payload", () => {
    const result = validateProjectCreate({
      ...EMPTY_PROJECT_CREATE_FORM,
      title: "  Records   modernization ",
      description: " Digitize public records. ",
      priority: "high",
      startDate: "2026-09-01",
      targetDate: "2026-10-01",
      initialMilestoneTitle: "First delivery",
      initialMilestoneDueDate: "2026-09-15"
    });

    expect(result.errors).toEqual({});
    expect(result.payload).toEqual({
      title: "Records modernization",
      description: "Digitize public records.",
      status: "planning",
      priority: "high",
      start_date: "2026-09-01",
      target_date: "2026-10-01",
      member_ids: [],
      milestones: [
        {
          title: "First delivery",
          description: "",
          due_date: "2026-09-15",
          sort_order: 0
        }
      ]
    });
  });

  it("rejects invalid schedules and milestones outside the project range", () => {
    const invalidSchedule = validateProjectCreate({
      ...EMPTY_PROJECT_CREATE_FORM,
      title: "Delivery",
      startDate: "2026-09-20",
      targetDate: "2026-09-10",
      initialMilestoneTitle: "First delivery",
      initialMilestoneDueDate: "2026-10-01"
    });

    expect(invalidSchedule.payload).toBeNull();
    expect(invalidSchedule.errors.targetDate).toMatch(/before/i);

    const invalidMilestone = validateProjectCreate({
      ...EMPTY_PROJECT_CREATE_FORM,
      title: "Delivery",
      startDate: "2026-09-01",
      targetDate: "2026-09-30",
      initialMilestoneTitle: "First delivery",
      initialMilestoneDueDate: "2026-10-01"
    });

    expect(invalidMilestone.payload).toBeNull();
    expect(invalidMilestone.errors.initialMilestoneDueDate).toMatch(/within/i);
  });

  it("rejects malformed dates, missing titles, and standalone milestone dates", () => {
    const result = validateProjectCreate({
      ...EMPTY_PROJECT_CREATE_FORM,
      startDate: "2026-02-30",
      initialMilestoneDueDate: "2026-09-10"
    });

    expect(result.payload).toBeNull();
    expect(result.errors.title).toBeTruthy();
    expect(result.errors.startDate).toMatch(/valid date/i);
    expect(result.errors.initialMilestoneTitle).toMatch(/title/i);
  });

  it("does not silently truncate an oversized milestone title", () => {
    const result = validateProjectCreate({
      ...EMPTY_PROJECT_CREATE_FORM,
      title: "Delivery",
      initialMilestoneTitle: "M".repeat(161)
    });

    expect(result.payload).toBeNull();
    expect(result.errors.initialMilestoneTitle).toMatch(/160/i);
  });
});
