import {
  PROJECT_OVERVIEW_SELECT,
  PROJECT_PAGE_SIZE,
  getProject,
  listProjects,
  normalizeProjectSearch,
  projectPageRange,
  projectSearchCacheKey
} from "@/features/projects/api/projects-api";
import { SupabaseUserError } from "@/lib/supabase/errors";

const mockFrom = jest.fn();

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({ from: mockFrom })
}));

const projectRow = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Records modernization",
  description: "Digitize records.",
  status: "active",
  priority: "high",
  start_date: "2026-08-01",
  target_date: "2026-09-01",
  program_title: "Digital services",
  owner_id: "22222222-2222-4222-8222-222222222222",
  org_id: "33333333-3333-4333-8333-333333333333",
  archived_at: null,
  updated_at: "2026-08-26T00:00:00+00:00"
};

function createQuery(result: unknown) {
  const query = {
    select: jest.fn(),
    order: jest.fn(),
    eq: jest.fn(),
    ilike: jest.fn(),
    range: jest.fn(),
    abortSignal: jest.fn(),
    maybeSingle: jest.fn()
  };
  query.select.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.ilike.mockReturnValue(query);
  query.range.mockResolvedValue(result);
  query.abortSignal.mockReturnValue(query);
  query.maybeSingle.mockResolvedValue(result);
  return query;
}

describe("project read API", () => {
  beforeEach(() => jest.clearAllMocks());

  it("uses a minimal, paged, title-only project query and maps the response", async () => {
    const query = createQuery({ data: [projectRow], error: null });
    mockFrom.mockReturnValue(query);

    await expect(listProjects({ page: 1, filter: "active", search: "  Records   modernization " })).resolves.toMatchObject([
      { id: projectRow.id, status: "active" }
    ]);

    expect(mockFrom).toHaveBeenCalledWith("projects");
    expect(query.select).toHaveBeenCalledWith(PROJECT_OVERVIEW_SELECT);
    expect(query.eq).toHaveBeenCalledWith("status", "active");
    expect(query.ilike).toHaveBeenCalledWith("title", "%Records modernization%");
    expect(query.range).toHaveBeenCalledWith(PROJECT_PAGE_SIZE, PROJECT_PAGE_SIZE * 2 - 1);
  });

  it("keeps direct detail reads unavailable when RLS hides the record", async () => {
    const query = createQuery({ data: null, error: null });
    mockFrom.mockReturnValue(query);

    await expect(getProject(projectRow.id)).resolves.toBeNull();
    expect(query.eq).toHaveBeenCalledWith("id", projectRow.id);
  });

  it("passes an AbortSignal through a direct project read", async () => {
    const query = createQuery({ data: projectRow, error: null });
    mockFrom.mockReturnValue(query);
    const controller = new AbortController();

    await expect(getProject(projectRow.id, controller.signal)).resolves.toMatchObject({
      id: projectRow.id
    });
    expect(query.abortSignal).toHaveBeenCalledWith(controller.signal);
  });

  it("maps Supabase failures to a redacted user error", async () => {
    const query = createQuery({ data: null, error: { code: "42501", message: "internal policy details" } });
    mockFrom.mockReturnValue(query);

    await expect(listProjects({ page: 0, filter: "all", search: "" })).rejects.toEqual(
      new SupabaseUserError("forbidden", "You do not have access to complete this action.")
    );
  });

  it("normalizes paging and search without putting the raw phrase in a cache key", () => {
    expect(projectPageRange(-1)).toEqual([0, PROJECT_PAGE_SIZE - 1]);
    expect(normalizeProjectSearch("  annual   delivery  ")).toBe("annual delivery");
    expect(projectSearchCacheKey("annual delivery")).not.toContain("annual delivery");
  });
});
