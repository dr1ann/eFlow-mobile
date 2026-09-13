const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
] as const;

export type ReviewSubmissionStatus =
  | "pending"
  | "approved"
  | "changes_requested"
  | "unknown";

export function reviewSubmissionStatusLabel(status: ReviewSubmissionStatus): string {
  switch (status) {
    case "pending":
      return "Awaiting review";
    case "approved":
      return "Approved";
    case "changes_requested":
      return "Changes requested";
    case "unknown":
      return "Status unavailable";
  }
}

/** Formats an ISO timestamp in UTC so a shared workflow reads consistently on every device. */
export function formatReviewTimestamp(value: string | null): string {
  if (!value) return "Time unavailable";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Time unavailable";

  const hour = String(date.getUTCHours()).padStart(2, "0");
  const minute = String(date.getUTCMinutes()).padStart(2, "0");
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCDate()}, ${date.getUTCFullYear()} · ${hour}:${minute} UTC`;
}
