import { mapTaskCommentRow } from "@/features/discussions/mappers";

describe("task comment mapper", () => {
  it("maps a text-only task comment", () => {
    expect(mapTaskCommentRow({
      id: "11111111-1111-4111-8111-111111111111",
      task_id: "22222222-2222-4222-8222-222222222222",
      author_id: null,
      author_name: "Team member",
      body: "I am awaiting the signed record.",
      created_at: "2026-08-26T00:00:00+00:00",
      edited_at: null,
      deleted_at: null
    })).toMatchObject({ body: "I am awaiting the signed record." });
  });
});
