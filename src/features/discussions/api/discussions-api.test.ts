import { sendTaskComment } from "@/features/discussions/api/discussions-api";

describe("task comment validation", () => {
  const input = {
    taskId: "11111111-1111-4111-8111-111111111111",
    authorId: "22222222-2222-4222-8222-222222222222",
    authorName: "Contributor",
    body: ""
  };

  it("does not create a request for empty or oversized comments", async () => {
    await expect(sendTaskComment(input)).rejects.toThrow("Enter a comment");
    await expect(sendTaskComment({ ...input, body: "a".repeat(2_001) })).rejects.toThrow("2,000");
  });
});
