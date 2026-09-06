import React from "react";
import { useLocalSearchParams } from "expo-router";
import { FlatList, Text, View } from "react-native";

import { Button } from "@/components/button";
import { FormField } from "@/components/form-field";
import { StatusNotice } from "@/components/status-notice";
import {
  reconcileChatMessages,
  validateChatMessage,
  type ChatChannelSummary,
  type ChatMessage
} from "@/contracts/chat";
import { useAuth } from "@/features/auth/auth-context";
import {
  createDevelopmentChatFixture,
  createDevelopmentChatMessage
} from "@/features/chat/development-fixtures";
import { parseUuidParam } from "@/lib/navigation/params";
import { isPhase3FixtureMode } from "@/lib/phase-3/capabilities";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface ChatChannelScreenViewProps {
  channel: ChatChannelSummary;
  draft: string;
  error: string | null;
  messages: readonly ChatMessage[];
  onDraftChange(value: string): void;
  onSend(): void;
}

export function ChatChannelScreenView({
  channel,
  draft,
  error,
  messages,
  onDraftChange,
  onSend
}: ChatChannelScreenViewProps) {
  return (
    <FlatList
      testID="chat-channel-screen"
      data={messages}
      keyExtractor={(message) => message.id}
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{ flexGrow: 1, gap: tokens.space.md, padding: tokens.space.lg }}
      ListHeaderComponent={
        <View style={{ gap: tokens.space.md, paddingBottom: tokens.space.sm }}>
          <View style={{ gap: tokens.space.xs }}>
            <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
              {channel.title}
            </Text>
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
              {channel.description}
            </Text>
          </View>
          <StatusNotice tone="warning">
            Development-only local preview. This does not send a chat message, update read state, or
            create a task comment.
          </StatusNotice>
        </View>
      }
      renderItem={({ item }) => <ChatMessageRow message={item} />}
      ListEmptyComponent={
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          No synthetic messages are available for this channel.
        </Text>
      }
      ListFooterComponent={
        <View style={{ gap: tokens.space.md, paddingTop: tokens.space.sm }}>
          <FormField
            label="Development message"
            value={draft}
            onChangeText={onDraftChange}
            error={error ?? undefined}
            placeholder="Add a local test message"
            autoCapitalize="sentences"
            multiline
            maxLength={2_000}
            textAlignVertical="top"
            style={{ minHeight: 108 }}
          />
          <Button label="Add local test message" onPress={onSend} />
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
            Edits, reactions, private attachments, Realtime, and retry behavior require their own
            verified server contracts and are not simulated as live operations.
          </Text>
        </View>
      }
    />
  );
}

function ChatMessageRow({ message }: { message: ChatMessage }) {
  return (
    <View
      style={{
        gap: tokens.space.xs,
        padding: tokens.space.md,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: colors.separator,
        backgroundColor: colors.surface
      }}
    >
      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: tokens.space.md }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "800" }}>
          {message.authorLabel}
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
          {message.delivery === "sent" ? "Local preview" : message.delivery}
        </Text>
      </View>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, lineHeight: 22 }}>
        {message.body}
      </Text>
    </View>
  );
}

export function ChatChannelScreen() {
  const { state } = useAuth();
  const params = useLocalSearchParams<{ "channel-id"?: string | string[] }>();
  const channelId = parseUuidParam(params["channel-id"]);

  if (state.kind !== "authorized") return null;
  if (!isPhase3FixtureMode()) {
    return <ChatContractGatedScreen message="Development chat preview is not enabled in this build." />;
  }
  if (!channelId) {
    return <ChatContractGatedScreen message="This development chat channel is unavailable." />;
  }

  return <AuthorizedDevelopmentChatChannelScreen channelId={channelId} userId={state.profile.id} />;
}

function AuthorizedDevelopmentChatChannelScreen({
  channelId,
  userId
}: {
  channelId: string;
  userId: string;
}) {
  const fixture = React.useMemo(() => createDevelopmentChatFixture(userId), [userId]);
  const channel = fixture.channels.find((candidate) => candidate.id === channelId) ?? null;
  const initialMessages = fixture.messagesByChannel[channelId] ?? [];

  if (!channel) {
    return <ChatContractGatedScreen message="This development chat channel is unavailable." />;
  }

  return (
    <DevelopmentChatChannelSession
      key={`${userId}:${channelId}`}
      channel={channel}
      initialMessages={initialMessages}
      userId={userId}
    />
  );
}

function DevelopmentChatChannelSession({
  channel,
  initialMessages,
  userId
}: {
  channel: ChatChannelSummary;
  initialMessages: readonly ChatMessage[];
  userId: string;
}) {
  const [messages, setMessages] = React.useState<ChatMessage[]>(() => [...initialMessages]);
  const [draft, setDraft] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);

  const send = (): void => {
    const validation = validateChatMessage(draft);
    if (!validation.value) {
      setError(validation.error);
      return;
    }

    setMessages((current) =>
      reconcileChatMessages(current, [createDevelopmentChatMessage(channel.id, userId, validation.value)])
    );
    setDraft("");
    setError(null);
  };

  return (
    <ChatChannelScreenView
      channel={channel}
      messages={messages}
      draft={draft}
      error={error}
      onDraftChange={(value) => {
        setDraft(value);
        setError(null);
      }}
      onSend={send}
    />
  );
}

function ChatContractGatedScreen({ message }: { message: string }) {
  return (
    <View
      testID="chat-channel-gated"
      style={{ flex: 1, padding: tokens.space.lg, backgroundColor: colors.background }}
    >
      <StatusNotice tone="warning">{message}</StatusNotice>
    </View>
  );
}
