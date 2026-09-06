import {
  createDevelopmentChatFixture,
  createDevelopmentChatMessage
} from "@/features/chat/development-fixtures";

const userId = "99999999-9999-4999-8999-999999999999";

describe("development chat fixtures", () => {
  it("contain only synthetic conversations and keep the current test account as the local author", () => {
    const fixture = createDevelopmentChatFixture(userId);

    expect(fixture.channels).toHaveLength(2);
    expect(fixture.messagesByChannel[fixture.channels[0]!.id]![0]!.body).toMatch(/synthetic/i);
    expect(fixture.messagesByChannel[fixture.channels[1]!.id]![0]!.authorId).toBe(userId);
  });

  it("creates a local-only message with separate canonical and request IDs", () => {
    const message = createDevelopmentChatMessage(
      "11111111-1111-4111-8111-111111111111",
      userId,
      "Development reply",
      "2026-09-03T09:00:00.000Z"
    );

    expect(message.authorId).toBe(userId);
    expect(message.clientRequestKey).not.toBe(message.id);
    expect(message.delivery).toBe("sent");
  });
});
