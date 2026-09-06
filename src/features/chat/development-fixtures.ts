import type { ChatChannelSummary, ChatMessage } from "@/contracts/chat";
import { createWorkflowUuid } from "@/lib/phase-1/ids";

const CHANNELS = [
  {
    id: "11111111-1111-4111-8111-111111111111",
    kind: "organization",
    title: "Development organization channel",
    description: "Synthetic conversation used only to test the mobile chat interface.",
    unreadCount: 1
  },
  {
    id: "22222222-2222-4222-8222-222222222222",
    kind: "task",
    title: "Development task channel",
    description: "Synthetic task-channel messages. Phase 1 task comments remain separate.",
    unreadCount: 0
  }
] as const satisfies readonly ChatChannelSummary[];

export interface DevelopmentChatFixture {
  channels: readonly ChatChannelSummary[];
  messagesByChannel: Readonly<Record<string, readonly ChatMessage[]>>;
}

/**
 * These records are deliberately synthetic and retained only in component
 * memory. They are never written to Supabase or sent to the gateway.
 */
export function createDevelopmentChatFixture(userId: string): DevelopmentChatFixture {
  return {
    channels: CHANNELS,
    messagesByChannel: {
      [CHANNELS[0].id]: [
        {
          id: "33333333-3333-4333-8333-333333333333",
          clientRequestKey: null,
          channelId: CHANNELS[0].id,
          authorId: "44444444-4444-4444-8444-444444444444",
          authorLabel: "Sample teammate",
          body: "This is synthetic development data. It is not an eFlow message.",
          createdAt: "2026-09-03T08:00:00.000Z",
          delivery: "sent"
        }
      ],
      [CHANNELS[1].id]: [
        {
          id: "55555555-5555-4555-8555-555555555555",
          clientRequestKey: null,
          channelId: CHANNELS[1].id,
          authorId: userId,
          authorLabel: "You",
          body: "This local preview does not submit task comments or chat messages.",
          createdAt: "2026-09-03T08:01:00.000Z",
          delivery: "sent"
        }
      ]
    }
  };
}

export function createDevelopmentChatMessage(
  channelId: string,
  userId: string,
  body: string,
  createdAt = new Date().toISOString()
): ChatMessage {
  const clientRequestKey = createWorkflowUuid();
  return {
    id: createWorkflowUuid(),
    clientRequestKey,
    channelId,
    authorId: userId,
    authorLabel: "You",
    body,
    createdAt,
    delivery: "sent"
  };
}
