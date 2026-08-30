export const PROJECT_STATUSES = [
  "planning",
  "active",
  "on_hold",
  "completed",
  "archived"
] as const;

export type ProjectStatus = (typeof PROJECT_STATUSES)[number];

export const PROJECT_PRIORITIES = ["low", "medium", "high"] as const;

export type ProjectPriority = (typeof PROJECT_PRIORITIES)[number];

export const PROJECT_FILTERS = ["all", ...PROJECT_STATUSES] as const;

export type ProjectFilter = (typeof PROJECT_FILTERS)[number];

const LEGACY_PROJECT_STATUS_ALIASES: Readonly<Record<string, ProjectStatus>> = {
  in_progress: "active",
  inprogress: "active",
  onhold: "on_hold"
};

export function toProjectStatus(value: string): ProjectStatus | null {
  if ((PROJECT_STATUSES as readonly string[]).includes(value)) {
    return value as ProjectStatus;
  }

  return LEGACY_PROJECT_STATUS_ALIASES[value.trim().toLowerCase()] ?? null;
}

export function isProjectPriority(value: string): value is ProjectPriority {
  return (PROJECT_PRIORITIES as readonly string[]).includes(value);
}

export function projectStatusLabel(status: ProjectStatus): string {
  switch (status) {
    case "planning":
      return "Planning";
    case "active":
      return "Active";
    case "on_hold":
      return "On hold";
    case "completed":
      return "Completed";
    case "archived":
      return "Archived";
  }
}

export function projectPriorityLabel(priority: ProjectPriority): string {
  switch (priority) {
    case "low":
      return "Low";
    case "medium":
      return "Medium";
    case "high":
      return "High";
  }
}

export interface ProjectOverview {
  id: string;
  title: string;
  description: string;
  status: ProjectStatus;
  priority: ProjectPriority;
  startDate: string | null;
  targetDate: string | null;
  programTitle: string | null;
  ownerId: string | null;
  organizationId: string | null;
  archivedAt: string | null;
  updatedAt: string;
}
