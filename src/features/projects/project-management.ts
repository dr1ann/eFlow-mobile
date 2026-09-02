import type { Json } from "@/contracts/database.types";
import type { ProjectPriority } from "@/contracts/projects";

export interface ProjectCreateFormValues {
  title: string;
  description: string;
  priority: ProjectPriority;
  startDate: string;
  targetDate: string;
  initialMilestoneTitle: string;
  initialMilestoneDueDate: string;
}

export interface ProjectCreateValidation {
  errors: Partial<Record<keyof ProjectCreateFormValues, string>>;
  payload: Json | null;
}

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function normalizeText(value: string, maximumLength: number): string {
  return value.trim().replace(/\s+/g, " ").slice(0, maximumLength);
}

function normalizeDate(value: string): string {
  return value.trim();
}

function isCalendarDate(value: string): boolean {
  if (!DATE_PATTERN.test(value)) return false;
  const [yearPart = "", monthPart = "", dayPart = ""] = value.split("-");
  const year = Number(yearPart);
  const month = Number(monthPart);
  const day = Number(dayPart);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/**
 * Builds the narrow project-create payload accepted by the server RPC. The
 * owner and organization are deliberately omitted: the backend derives them
 * from the authenticated Department Head and its authorized scope.
 */
export function validateProjectCreate(values: ProjectCreateFormValues): ProjectCreateValidation {
  const title = normalizeText(values.title, 160);
  const description = values.description.trim().slice(0, 4_000);
  const startDate = normalizeDate(values.startDate);
  const targetDate = normalizeDate(values.targetDate);
  const milestoneTitle = normalizeText(values.initialMilestoneTitle, 160);
  const milestoneDueDate = normalizeDate(values.initialMilestoneDueDate);
  const errors: ProjectCreateValidation["errors"] = {};

  if (!title) errors.title = "A project title is required.";
  if (values.title.trim().length > 160) errors.title = "Project titles must be 160 characters or fewer.";
  if (values.description.trim().length > 4_000) {
    errors.description = "Descriptions must be 4,000 characters or fewer.";
  }
  if (startDate && !isCalendarDate(startDate)) errors.startDate = "Use a valid date in YYYY-MM-DD format.";
  if (targetDate && !isCalendarDate(targetDate)) errors.targetDate = "Use a valid date in YYYY-MM-DD format.";
  if (!errors.startDate && !errors.targetDate && startDate && targetDate && targetDate < startDate) {
    errors.targetDate = "The target date cannot be before the start date.";
  }
  if (milestoneDueDate && !milestoneTitle) {
    errors.initialMilestoneTitle = "Add a milestone title before setting its due date.";
  }
  if (values.initialMilestoneTitle.trim().length > 160) {
    errors.initialMilestoneTitle = "Milestone titles must be 160 characters or fewer.";
  }
  if (milestoneTitle && milestoneDueDate && !isCalendarDate(milestoneDueDate)) {
    errors.initialMilestoneDueDate = "Use a valid date in YYYY-MM-DD format.";
  }
  if (
    milestoneDueDate &&
    !errors.initialMilestoneDueDate &&
    !errors.startDate &&
    !errors.targetDate &&
    ((startDate && milestoneDueDate < startDate) || (targetDate && milestoneDueDate > targetDate))
  ) {
    errors.initialMilestoneDueDate = "The milestone date must be within the project schedule.";
  }

  if (Object.keys(errors).length > 0) return { errors, payload: null };

  return {
    errors,
    payload: {
      title,
      description,
      status: "planning",
      priority: values.priority,
      start_date: startDate || "",
      target_date: targetDate || "",
      member_ids: [],
      milestones: milestoneTitle
        ? [
            {
              title: milestoneTitle,
              description: "",
              due_date: milestoneDueDate || "",
              sort_order: 0
            }
          ]
        : []
    }
  };
}

export const EMPTY_PROJECT_CREATE_FORM: ProjectCreateFormValues = {
  title: "",
  description: "",
  priority: "medium",
  startDate: "",
  targetDate: "",
  initialMilestoneTitle: "",
  initialMilestoneDueDate: ""
};
