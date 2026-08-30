import type { ProjectFilter, ProjectOverview } from "@/contracts/projects";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

import { mapProjectOverviewRow } from "../mappers";

export const PROJECT_PAGE_SIZE = 25;

export const PROJECT_OVERVIEW_SELECT =
  "id,title,description,status,priority,start_date,target_date,program_title,owner_id,org_id,archived_at,updated_at";

export interface ProjectPageRequest {
  page: number;
  filter: ProjectFilter;
  search: string;
  signal?: AbortSignal;
}

export function projectPageRange(page: number): [number, number] {
  const start = Math.max(0, page) * PROJECT_PAGE_SIZE;
  return [start, start + PROJECT_PAGE_SIZE - 1];
}

export function normalizeProjectSearch(value: string): string {
  return value.trim().replace(/\s+/g, " ").slice(0, 100);
}

function projectSearchPattern(search: string): string {
  return `%${normalizeProjectSearch(search).replace(/[\\%_]/g, "\\$&")}%`;
}

/**
 * Keeps the raw search phrase out of React Query keys while still separating
 * cache entries. It is not used for security; RLS remains the data boundary.
 */
export function projectSearchCacheKey(search: string): string {
  const normalized = normalizeProjectSearch(search);
  let hash = 2_166_136_261;
  for (let index = 0; index < normalized.length; index += 1) {
    hash ^= normalized.charCodeAt(index);
    hash = Math.imul(hash, 16_777_619);
  }

  return `${normalized.length}-${(hash >>> 0).toString(36)}`;
}

export async function listProjects({
  page,
  filter,
  search,
  signal
}: ProjectPageRequest): Promise<readonly ProjectOverview[]> {
  const [from, to] = projectPageRange(page);
  let request = getSupabaseClient()
    .from("projects")
    .select(PROJECT_OVERVIEW_SELECT)
    .order("updated_at", { ascending: false })
    .order("id", { ascending: true });

  if (filter !== "all") request = request.eq("status", filter);
  if (normalizeProjectSearch(search)) request = request.ilike("title", projectSearchPattern(search));

  const pageRequest = request.range(from, to);
  const { data, error } = await (signal ? pageRequest.abortSignal(signal) : pageRequest);

  if (error) throw toSupabaseUserError(error);
  return (data ?? []).map(mapProjectOverviewRow);
}

export async function getProject(
  projectId: string,
  signal?: AbortSignal
): Promise<ProjectOverview | null> {
  let request = getSupabaseClient()
    .from("projects")
    .select(PROJECT_OVERVIEW_SELECT)
    .eq("id", projectId);
  if (signal) request = request.abortSignal(signal);

  const { data, error } = await request.maybeSingle();
  if (error) throw toSupabaseUserError(error);
  return data ? mapProjectOverviewRow(data) : null;
}
