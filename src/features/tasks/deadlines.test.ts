import {
  deadlineGroupForDate,
  isDateDueSoon,
  matchesDeadlineFilter,
  toDeviceCalendarDate
} from "@/features/tasks/deadlines";

describe("mobile deadline policy", () => {
  it("keeps date-only deadlines on the device's local calendar date", () => {
    const deadline = toDeviceCalendarDate("2026-09-15");

    expect(deadline).not.toBeNull();
    expect(deadline?.getFullYear()).toBe(2026);
    expect(deadline?.getMonth()).toBe(8);
    expect(deadline?.getDate()).toBe(15);
  });

  it("changes the deadline group at the local midnight boundary", () => {
    const beforeMidnight = new Date(2026, 8, 15, 23, 59, 59);
    const afterMidnight = new Date(2026, 8, 16, 0, 0, 1);

    expect(deadlineGroupForDate("2026-09-15", beforeMidnight)).toBe("today");
    expect(deadlineGroupForDate("2026-09-15", afterMidnight)).toBe("overdue");
    expect(deadlineGroupForDate("2026-09-16", afterMidnight)).toBe("today");
  });

  it("converts timestamp deadlines to the device's local calendar before filtering", () => {
    const localTimestamp = new Date(2026, 8, 16, 0, 30, 0).toISOString();
    const deviceDate = toDeviceCalendarDate(localTimestamp);
    const now = new Date(2026, 8, 15, 12, 0, 0);

    expect(deviceDate).not.toBeNull();
    expect(deviceDate?.getFullYear()).toBe(2026);
    expect(deviceDate?.getMonth()).toBe(8);
    expect(deviceDate?.getDate()).toBe(16);
    expect(isDateDueSoon(localTimestamp, now)).toBe(true);
    expect(matchesDeadlineFilter(localTimestamp, "overdue", now)).toBe(false);
  });

  it("keeps due-soon bounded to today through the next seven calendar days", () => {
    const now = new Date(2026, 8, 15, 8, 0, 0);

    expect(isDateDueSoon("2026-09-15", now)).toBe(true);
    expect(isDateDueSoon("2026-09-22", now)).toBe(true);
    expect(isDateDueSoon("2026-09-23", now)).toBe(false);
    expect(matchesDeadlineFilter("not-a-date", "due_soon", now)).toBe(false);
  });
});
