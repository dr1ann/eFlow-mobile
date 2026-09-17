/**
 * Mobile deadline policy:
 *
 * - A date-only value is a calendar date in the device's local time zone.
 * - A timestamp is converted to the device's local calendar date before it is
 *   compared or displayed.
 *
 * This keeps work discovery honest around midnight. Server reminder timing is
 * a separate backend concern and is not inferred by this client helper.
 */
export type DeadlineGroup = "overdue" | "today" | "upcoming" | "unscheduled";
export type DeadlineFilter = "all" | "overdue" | "due_soon";

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/;

function isSameLocalDate(date: Date, year: number, monthIndex: number, day: number): boolean {
  return (
    date.getFullYear() === year &&
    date.getMonth() === monthIndex &&
    date.getDate() === day
  );
}

export function toDeviceCalendarDate(value: string | null): Date | null {
  if (!value) return null;

  const dateOnly = DATE_ONLY.exec(value);
  if (dateOnly) {
    const year = Number(dateOnly[1]);
    const monthIndex = Number(dateOnly[2]) - 1;
    const day = Number(dateOnly[3]);
    const localDate = new Date(year, monthIndex, day);
    return isSameLocalDate(localDate, year, monthIndex, day) ? localDate : null;
  }

  const timestamp = new Date(value);
  if (Number.isNaN(timestamp.getTime())) return null;

  return new Date(timestamp.getFullYear(), timestamp.getMonth(), timestamp.getDate());
}

export function startOfDeviceDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

export function addDeviceCalendarDays(value: Date, days: number): Date {
  const result = startOfDeviceDay(value);
  result.setDate(result.getDate() + days);
  return result;
}

export function deadlineGroupForDate(value: string | null, now: Date): DeadlineGroup {
  const deadline = toDeviceCalendarDate(value);
  if (!deadline) return "unscheduled";

  const today = startOfDeviceDay(now);
  if (deadline.getTime() < today.getTime()) return "overdue";
  if (deadline.getTime() === today.getTime()) return "today";
  return "upcoming";
}

export function isDateDueSoon(value: string | null, now: Date, days = 7): boolean {
  const deadline = toDeviceCalendarDate(value);
  if (!deadline) return false;

  const today = startOfDeviceDay(now);
  const lastDueSoonDay = addDeviceCalendarDays(today, Math.max(0, days));
  return deadline.getTime() >= today.getTime() && deadline.getTime() <= lastDueSoonDay.getTime();
}

export function matchesDeadlineFilter(
  value: string | null,
  filter: DeadlineFilter,
  now: Date
): boolean {
  switch (filter) {
    case "all":
      return true;
    case "overdue":
      return deadlineGroupForDate(value, now) === "overdue";
    case "due_soon":
      return isDateDueSoon(value, now);
  }
}
