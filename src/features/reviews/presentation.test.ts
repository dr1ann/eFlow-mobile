import {
  formatReviewTimestamp,
  reviewSubmissionStatusLabel
} from "@/features/reviews/presentation";

describe("review presentation", () => {
  it("formats shared decision times in UTC and redacts malformed values", () => {
    expect(formatReviewTimestamp("2026-09-06T13:05:00.000Z")).toBe("Sep 6, 2026 · 13:05 UTC");
    expect(formatReviewTimestamp(null)).toBe("Time unavailable");
    expect(formatReviewTimestamp("not-a-timestamp")).toBe("Time unavailable");
  });

  it("uses clear labels for every persisted review state", () => {
    expect(reviewSubmissionStatusLabel("pending")).toBe("Awaiting review");
    expect(reviewSubmissionStatusLabel("approved")).toBe("Approved");
    expect(reviewSubmissionStatusLabel("changes_requested")).toBe("Changes requested");
    expect(reviewSubmissionStatusLabel("unknown")).toBe("Status unavailable");
  });
});
