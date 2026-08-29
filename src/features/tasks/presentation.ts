import type { TaskFilter } from "@/contracts/tasks";

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

export const TASK_FILTER_LABELS: Record<TaskFilter, string> = {
  active: "Active",
  waiting: "Waiting",
  review: "In review",
  changes_requested: "Changes requested",
  completed: "Completed",
  history: "History"
};

export function formatTaskDate(value: string | null): string {
  if (!value) return "No deadline";
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return "Date unavailable";

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const timestamp = Date.UTC(year, month - 1, day);
  const date = new Date(timestamp);
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return "Date unavailable";
  }

  return `${MONTHS[month - 1]} ${day}, ${year}`;
}

export function formatEvidenceSize(size: number | null): string {
  if (size === null) return "Size unavailable";
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}
