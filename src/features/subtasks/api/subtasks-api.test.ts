import { listSubtaskSubmissionAttachments } from "@/features/subtasks/api/subtasks-api";
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
});
