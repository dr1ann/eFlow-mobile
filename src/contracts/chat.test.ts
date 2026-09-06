import {
  CHAT_MESSAGE_MAX_LENGTH,
  reconcileChatMessages,
  sortChatMessages,
  validateChatMessage,
  type ChatMessage
} from "@/contracts/chat";

const baseMessage: ChatMessage = {
  id: "11111111-1111-4111-8111-111111111111",
  clientRequestKey: null,
  channelId: "22222222-2222-4222-8222-222222222222",
  authorId: "33333333-3333-4333-8333-333333333333",
  authorLabel: "You",
  body: "Status update",
  createdAt: "2026-09-03T01:00:00.000Z",
  delivery: "sent"
};

describe("chat contracts", () => {
  it("trims valid compose drafts and rejects empty or oversized text", () => {
    expect(validateChatMessage("  Hello team  ")).toEqual({ value: "Hello team", error: null });
    expect(validateChatMessage("   ").error).toMatch(/Enter a message/i);
    expect(validateChatMessage("a".repeat(CHAT_MESSAGE_MAX_LENGTH + 1)).error).toMatch(/2,000/i);
  });

  it("orders timestamp ties deterministically and reconciles an optimistic send", () => {
    const later = {
      ...baseMessage,
      id: "44444444-4444-4444-8444-444444444444",
      createdAt: "2026-09-03T02:00:00.000Z"
    };
    expect(sortChatMessages([later, baseMessage])).toEqual([baseMessage, later]);

    const optimistic = {
      ...baseMessage,
      id: "55555555-5555-4555-8555-555555555555",
      clientRequestKey: "request-1",
      delivery: "sending" as const
    };
    const canonical = {
      ...optimistic,
      id: "66666666-6666-4666-8666-666666666666",
      delivery: "sent" as const
    };

    expect(reconcileChatMessages([optimistic], [canonical])).toEqual([canonical]);
  });

  it("ignores malformed incoming IDs rather than rendering them", () => {
    expect(reconcileChatMessages([], [{ ...baseMessage, id: "not-a-uuid" }])).toEqual([]);
  });
});
