import {
  leadingTaskOwnershipFilter,
  listMyTasks,
  listTasksByProject,
  listTaskAttachments,
  myTaskOwnershipFilter,
  taskStatusesForFilter
} from "@/features/tasks/api/tasks-api";
import { SupabaseUserError } from "@/lib/supabase/errors";

const mockFrom = jest.fn();

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({ from: mockFrom })
}));

const userId = "11111111-1111-4111-8111-111111111111";
const taskId = "22222222-2222-4222-8222-222222222222";
const submissionId = "33333333-3333-4333-8333-333333333333";

function createQuery(result: unknown) {
  const query = {
    select: jest.fn(),
    eq: jest.fn(),
    is: jest.fn(),
    or: jest.fn(),
    in: jest.fn(),
    order: jest.fn(),
    range: jest.fn(),
    abortSignal: jest.fn()
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.is.mockReturnValue(query);
  query.or.mockReturnValue(query);
  query.in.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.range.mockReturnValue(query);
  query.abortSignal.mockReturnValue(query);
  Object.assign(query, {
    then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve)
  });
  return query;
}

describe("task ownership query filters", () => {
  beforeEach(() => jest.clearAllMocks());

  it("includes team membership and the unassigned recommendation fallback for My Tasks", () => {
    expect(myTaskOwnershipFilter(userId)).toBe(
      `assigned_to.eq.${userId},team_member_ids.cs.{${userId}},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`
    );
  });

  it("never treats a stale recommendation as leadership after assignment", () => {
    expect(leadingTaskOwnershipFilter(userId)).toBe(
      `assigned_to.eq.${userId},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`
    );
  });

  it("applies task status filters before pagination instead of filtering one loaded page", async () => {
    const query = createQuery({ data: [], error: null });
    mockFrom.mockReturnValue(query);

    await expect(listMyTasks(userId, { page: 1, filter: "active" })).resolves.toEqual([]);

    expect(query.or).toHaveBeenCalledWith(myTaskOwnershipFilter(userId));
    expect(query.in).toHaveBeenCalledWith("status", ["todo", "in_progress"]);
    expect(query.range).toHaveBeenCalledWith(30, 59);
    expect(taskStatusesForFilter("history")).toEqual(["completed", "cancelled"]);
  });

  it("uses the canonical linked project relation for paged project work", async () => {
    const query = createQuery({ data: [], error: null });
    mockFrom.mockReturnValue(query);
    const projectId = "44444444-4444-4444-8444-444444444444";

    await expect(listTasksByProject(projectId, { page: 0 })).resolves.toEqual([]);

    expect(query.eq).toHaveBeenCalledWith("linked_project_id", projectId);
    expect(query.is).toHaveBeenCalledWith("deleted_at", null);
    expect(query.order).toHaveBeenNthCalledWith(1, "due_date", { ascending: true, nullsFirst: false });
    expect(query.order).toHaveBeenNthCalledWith(2, "id", { ascending: true });
  });

  it("reads parent evidence only for the selected immutable submission attempt", async () => {
    const query = createQuery({ data: [], error: null });
    mockFrom.mockReturnValue(query);
    const controller = new AbortController();

    await expect(listTaskAttachments(taskId, submissionId, controller.signal)).resolves.toEqual([]);

    expect(mockFrom).toHaveBeenCalledWith("task_attachments");
    expect(query.eq).toHaveBeenNthCalledWith(1, "task_id", taskId);
    expect(query.eq).toHaveBeenNthCalledWith(2, "submission_id", submissionId);
    expect(query.abortSignal).toHaveBeenCalledWith(controller.signal);
  });

  it("redacts an attempt read denied by Storage policy", async () => {
    const query = createQuery({
      data: null,
      error: { code: "42501", message: "private submission evidence policy" }
    });
    mockFrom.mockReturnValue(query);

    await expect(listTaskAttachments(taskId, submissionId)).rejects.toEqual(
      new SupabaseUserError("forbidden", "You do not have access to complete this action.")
    );
  });
});
