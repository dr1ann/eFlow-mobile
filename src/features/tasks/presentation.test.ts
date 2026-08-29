import { formatEvidenceSize, formatTaskDate } from "@/features/tasks/presentation";

describe("task presentation", () => {
  it("formats stable date-only values without shifting time zones", () => {
    expect(formatTaskDate("2026-08-29")).toBe("Aug 29, 2026");
    expect(formatTaskDate("2026-02-31")).toBe("Date unavailable");
    expect(formatTaskDate(null)).toBe("No deadline");
  });

  it("formats evidence sizes without exposing a device URI", () => {
    expect(formatEvidenceSize(512)).toBe("512 B");
    expect(formatEvidenceSize(1536)).toBe("1.5 KB");
    expect(formatEvidenceSize(2 * 1024 * 1024)).toBe("2.0 MB");
    expect(formatEvidenceSize(null)).toBe("Size unavailable");
  });
});
