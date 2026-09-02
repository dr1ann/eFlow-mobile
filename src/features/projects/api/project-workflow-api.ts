import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import type { Json } from "@/contracts/database.types";
import { toProjectStatus, type ProjectOverview, type ProjectStatus } from "@/contracts/projects";
import { requireCurrentOnlineMutation } from "@/lib/phase-1/online";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapProjectOverviewRow } from "../mappers";

export type ProjectCompletionBlockerKind =
  | "work"
  | "task"
  | "subtask"
  | "financial"
  | "governance"
  | "unknown";

export interface ProjectCompletionBlocker {
  kind: ProjectCompletionBlockerKind;
  title: string;
  detail: string;
  taskId: string | null;
}

export interface ProjectCompletionReadiness {
  projectId: string;
  title: string;
  status: ProjectStatus;
  canComplete: boolean;
  blockers: readonly ProjectCompletionBlocker[];
}

const readinessSchema = z.object({
  projectId: z.string().uuid(),
  title: z.string().trim().min(1),
  status: z.string(),
  canComplete: z.boolean(),
  blockers: z.array(
    z.object({
      kind: z.string(),
      title: z.string().trim().min(1),
      detail: z.string().trim().min(1),
      taskId: z.string().uuid().optional()
    }).passthrough()
  )
});

function completionBlockerKind(value: string): ProjectCompletionBlockerKind {
  switch (value) {
    case "work":
    case "task":
    case "subtask":
    case "governance":
      return value;
    case "cash":
    case "financial":
      return "financial";
    default:
      return "unknown";
  }
}

/**
 * Maps the closeout RPC to a deliberately narrow mobile DTO. Cash blockers
 * are redacted because Phase 2 does not expose finance workflows or amounts.
 */
export function mapProjectCompletionReadiness(raw: unknown): ProjectCompletionReadiness {
  const parsed = readinessSchema.safeParse(raw);
  if (!parsed.success) throw new ContractMappingError("project completion readiness");

  const status = toProjectStatus(parsed.data.status);
  if (!status) throw new ContractMappingError("project completion readiness");

  return {
    projectId: parsed.data.projectId,
    title: parsed.data.title,
    status,
    canComplete: parsed.data.canComplete,
    blockers: parsed.data.blockers.map((blocker) => {
      const kind = completionBlockerKind(blocker.kind);
      if (kind === "financial") {
        return {
          kind,
          title: "Financial clearance",
          detail: "Financial clearance must be resolved on the web before this project can be completed.",
          taskId: null
        };
      }
      if (kind === "unknown") {
        return {
          kind,
          title: "Additional closeout requirement",
          detail: "Open the project on the web to resolve this completion requirement.",
          taskId: null
        };
      }
      return {
        kind,
        title: blocker.title,
        detail: blocker.detail,
        taskId: blocker.taskId ?? null
      };
    })
  };
}

/** Creates one planning project through the server-owned atomic RPC. */
export async function createProjectWithDetails(payload: Json): Promise<ProjectOverview> {
  requireCurrentOnlineMutation();
  const { data, error } = await getSupabaseClient().rpc("create_project_with_details", {
    p_payload: payload
  });
  if (error) throw toSupabaseUserError(error);
  return mapProjectOverviewRow(data);
}

/** Reads closeout readiness only through the project-manager-authorized RPC. */
export async function getProjectCompletionReadiness(
  projectId: string
): Promise<ProjectCompletionReadiness> {
  const { data, error } = await getSupabaseClient().rpc("get_project_completion_readiness", {
    p_project_id: projectId
  });
  if (error) throw toSupabaseUserError(error);
  return mapProjectCompletionReadiness(data);
}

/** Marks an eligible project complete; the database rechecks readiness atomically. */
export async function completeProject(projectId: string, note: string): Promise<void> {
  requireCurrentOnlineMutation();
  const { error } = await getSupabaseClient().rpc("complete_project", {
    p_project_id: projectId,
    p_note: note.trim() || undefined
  });
  if (error) throw toSupabaseUserError(error);
}

/** Archives an already-completed project; the database rechecks lifecycle rules. */
export async function archiveCompletedProject(projectId: string, reason: string): Promise<void> {
  requireCurrentOnlineMutation();
  const { error } = await getSupabaseClient().rpc("archive_completed_project", {
    p_project_id: projectId,
    p_reason: reason.trim() || undefined
  });
  if (error) throw toSupabaseUserError(error);
}
