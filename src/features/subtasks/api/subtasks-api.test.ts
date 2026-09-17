import {
  listMySubtasks,
  listSubtaskSubmissionAttachments,
  subtaskStatusesForFilter
} from "@/features/subtasks/api/subtasks-api";
import { SupabaseUserError } from "@/lib/supabase/errors";

const mockFrom = jest.fn();

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({ from: mockFrom })
}));

const submissionId = "11111111-1111-4111-8111-111111111111";

function createQuery(result: unknown) {
  const query = {
    select: jest.fn(),
    eq: jest.fn(),
    or: jest.fn(),
    in: jest.fn(),
    order: jest.fn(),
    range: jest.fn(),
    abortSignal: jest.fn()
  };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
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

describe("subtask evidence reads", () => {
  beforeEach(() => jest.clearAllMocks());

  it("scopes every metadata read to the selected immutable submission attempt", async () => {
    const query = createQuery({ data: [], error: null });
    mockFrom.mockReturnValue(query);
    const controller = new AbortController();

    await expect(listSubtaskSubmissionAttachments(submissionId, controller.signal)).resolves.toEqual([]);

    expect(mockFrom).toHaveBeenCalledWith("subtask_submission_attachments");
    expect(query.eq).toHaveBeenCalledWith("submission_id", submissionId);
    expect(query.abortSignal).toHaveBeenCalledWith(controller.signal);
  });

  it("redacts a denied attachment read", async () => {
    const query = createQuery({
      data: null,
      error: { code: "42501", message: "private subtask evidence policy" }
    });
    mockFrom.mockReturnValue(query);

    await expect(listSubtaskSubmissionAttachments(submissionId)).rejects.toEqual(
      new SupabaseUserError("forbidden", "You do not have access to complete this action.")
    );
  });

  it("discovers direct subtask assignees with server-side status filtering and stable ordering", async () => {
    const query = createQuery({ data: [], error: null });
    mockFrom.mockReturnValue(query);
    const userId = "22222222-2222-4222-8222-222222222222";

    await expect(listMySubtasks(userId, { page: 0, filter: "active" })).resolves.toEqual([]);

    expect(query.or).toHaveBeenCalledWith(`assigned_to.eq.${userId},assigned_to_ids.cs.{${userId}}`);
    expect(query.in).toHaveBeenCalledWith("status", ["todo", "in_progress"]);
    expect(query.order).toHaveBeenNthCalledWith(1, "due_date", { ascending: true, nullsFirst: false });
    expect(query.order).toHaveBeenNthCalledWith(2, "position", { ascending: true });
    expect(query.order).toHaveBeenNthCalledWith(3, "id", { ascending: true });
    expect(subtaskStatusesForFilter("history")).toEqual(["completed"]);
  });
});
