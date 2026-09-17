import type { TaskFilter } from "@/contracts/tasks";
import { toDeviceCalendarDate } from "@/features/tasks/deadlines";

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
  review: "Awaiting review",
  changes_requested: "Changes requested",
  completed: "Completed",
  history: "History"
};

export function formatTaskDate(value: string | null): string {
  if (!value) return "No deadline";
  const date = toDeviceCalendarDate(value);
  if (!date) return "Date unavailable";
  return `${MONTHS[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
}

export function formatEvidenceSize(size: number | null): string {
  if (size === null) return "Size unavailable";
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}
