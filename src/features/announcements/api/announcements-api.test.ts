import { listRecipientAnnouncements } from "@/features/announcements/api/announcements-api";

const mockFrom = jest.fn();

jest.mock("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({ from: mockFrom }) }));

const ids = {
  user: "11111111-1111-4111-8111-111111111111",
  announcement: "22222222-2222-4222-8222-222222222222"
};

function recipientQuery(result: unknown) {
  const query = { select: jest.fn(), eq: jest.fn(), order: jest.fn(), range: jest.fn(), abortSignal: jest.fn() };
  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.range.mockResolvedValue(result);
  query.abortSignal.mockReturnValue(query);
  return query;
}

function announcementQuery(result: unknown) {
  const query = { select: jest.fn(), in: jest.fn(), eq: jest.fn(), order: jest.fn(), abortSignal: jest.fn() };
  query.select.mockReturnValue(query);
  query.in.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.order.mockReturnValue(query);
  query.abortSignal.mockReturnValue(query);
  Object.assign(query, { then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve) });
  return query;
}

describe("recipient announcement reads", () => {
  beforeEach(() => jest.clearAllMocks());

  it("uses the recipient scope before requesting only published, non-expired notices", async () => {
    const recipients = recipientQuery({ data: [{ announcement_id: ids.announcement }], error: null });
    const announcements = announcementQuery({ data: [{
      id: ids.announcement,
      title: "Service notice",
      body: "Work will resume.",
      status: "published",
      audience: "all",
      published_at: "2026-08-30T00:00:00Z",
      expires_at: "2026-09-30T00:00:00Z",
      created_at: "2026-08-30T00:00:00Z",
      updated_at: "2026-08-30T00:00:00Z"
    }], error: null });
    mockFrom.mockReturnValueOnce(recipients).mockReturnValueOnce(announcements);

    await expect(listRecipientAnnouncements(ids.user, 0)).resolves.toMatchObject([{ id: ids.announcement }]);
    expect(recipients.eq).toHaveBeenCalledWith("user_id", ids.user);
    expect(announcements.in).toHaveBeenCalledWith("id", [ids.announcement]);
    expect(announcements.eq).toHaveBeenCalledWith("status", "published");
  });
});
