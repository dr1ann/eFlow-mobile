import { z } from "zod";

export const CHAT_CHANNEL_PAGE_SIZE = 25;
export const CHAT_MESSAGE_PAGE_SIZE = 50;
export const CHAT_MESSAGE_MAX_LENGTH = 2_000;

export type ChatChannelKind = "organization" | "task";
export type ChatMessageDelivery = "sending" | "sent" | "failed";

export interface ChatChannelSummary {
  id: string;
  kind: ChatChannelKind;
  title: string;
  description: string;
  unreadCount: number;
}

export interface ChatMessage {
  id: string;
  clientRequestKey: string | null;
  channelId: string;
  authorId: string;
  authorLabel: string;
  body: string;
  createdAt: string;
  delivery: ChatMessageDelivery;
}

export type ChatMessageValidation =
  | { value: string; error: null }
  | { value: null; error: string };

/** Validates only a local compose draft; the server remains authoritative. */
export function validateChatMessage(value: string): ChatMessageValidation {
  const body = value.trim();
  if (!body) return { value: null, error: "Enter a message before sending." };
  if (body.length > CHAT_MESSAGE_MAX_LENGTH) {
    return { value: null, error: `Messages must be ${CHAT_MESSAGE_MAX_LENGTH.toLocaleString()} characters or fewer.` };
  }
  return { value: body, error: null };
}

const messageIdSchema = z.string().uuid();

/** Orders by server-style timestamp, then stable ID for deterministic ties. */
export function sortChatMessages(messages: readonly ChatMessage[]): ChatMessage[] {
  return [...messages].sort((left, right) => {
    const createdAt = left.createdAt.localeCompare(right.createdAt);
    if (createdAt !== 0) return createdAt;
    return left.id.localeCompare(right.id);
  });
}

/**
 * Reconciles a server event with an optimistic message using canonical ID first
 * and client request key second. It is safe for development fixtures and ready
 * for a future server-issued idempotency contract.
 */
export function reconcileChatMessages(
  current: readonly ChatMessage[],
  incoming: readonly ChatMessage[]
): ChatMessage[] {
  const byIdentity = new Map<string, ChatMessage>();

  for (const message of current) {
    byIdentity.set(message.clientRequestKey ?? message.id, message);
  }
  for (const message of incoming) {
    const id = messageIdSchema.safeParse(message.id);
    if (!id.success) continue;
    byIdentity.set(message.clientRequestKey ?? message.id, message);
  }

  return sortChatMessages([...byIdentity.values()]);
}
