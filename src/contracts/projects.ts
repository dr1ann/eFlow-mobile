export interface ProjectOverview {
  id: string;
  title: string;
  description: string;
  status: string;
  priority: string;
  startDate: string | null;
  targetDate: string | null;
  programTitle: string | null;
  archivedAt: string | null;
  updatedAt: string;
}
