import {
  leadingTaskOwnershipFilter,
  listTaskAttachments,
  myTaskOwnershipFilter
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
    order: jest.fn(),
    abortSignal: jest.fn()
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.order.mockReturnValue(query);
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
