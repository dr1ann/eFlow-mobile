import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import type { ProjectOverview } from "@/contracts/projects";

const projectRowSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(1),
  description: z.string(),
  status: z.string(),
  priority: z.string(),
  start_date: z.string().nullable(),
  target_date: z.string().nullable(),
  program_title: z.string().nullable(),
  archived_at: z.string().nullable(),
  updated_at: z.string()
});

export function mapProjectOverviewRow(row: unknown): ProjectOverview {
  const parsed = projectRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("project");

  const data = parsed.data;
  return {
    id: data.id,
    title: data.title,
    description: data.description,
    status: data.status,
    priority: data.priority,
    startDate: data.start_date,
    targetDate: data.target_date,
    programTitle: data.program_title,
    archivedAt: data.archived_at,
    updatedAt: data.updated_at
  };
}
