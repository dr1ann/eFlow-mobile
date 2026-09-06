import { useRouter } from "expo-router";
import { Pressable, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import type { ChatChannelSummary } from "@/contracts/chat";
import { useAuth } from "@/features/auth/auth-context";
import { createDevelopmentChatFixture } from "@/features/chat/development-fixtures";
import { isPhase3FixtureMode } from "@/lib/phase-3/capabilities";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface ChatChannelListScreenViewProps {
  channels: readonly ChatChannelSummary[];
  onOpenChannel(channelId: string): void;
}

export function ChatChannelListScreenView({
  channels,
  onOpenChannel
}: ChatChannelListScreenViewProps) {
  return (
    <AppScreen testID="chat-channel-list-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Chat preview
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
          Exercise the mobile chat layout using only synthetic development data.
        </Text>
      </View>

      <StatusNotice tone="warning">
        Development-only preview: no channel membership, message, or read state is loaded from or
        written to eFlow. Live chat remains disabled until its server authorization contract is verified.
      </StatusNotice>

      <View style={{ gap: tokens.space.md }}>
        {channels.map((channel) => (
          <Pressable
            key={channel.id}
            accessibilityRole="button"
            accessibilityLabel={`Open development chat ${channel.title}. ${channel.unreadCount} unread.`}
            onPress={() => onOpenChannel(channel.id)}
            style={({ pressed }) => ({
              minHeight: tokens.touchTarget,
              gap: tokens.space.sm,
              padding: tokens.space.lg,
              borderRadius: tokens.radius.md,
              borderCurve: "continuous",
              borderWidth: 1,
              borderColor: colors.separator,
              backgroundColor: colors.surface,
              opacity: pressed ? 0.78 : 1
            })}
          >
            <View style={{ flexDirection: "row", justifyContent: "space-between", gap: tokens.space.md }}>
              <Text selectable style={{ flex: 1, color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
                {channel.title}
              </Text>
              {channel.unreadCount > 0 ? (
                <Text selectable style={{ color: colors.primary, fontSize: tokens.type.caption, fontWeight: "700" }}>
                  {channel.unreadCount} unread
                </Text>
              ) : null}
            </View>
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
              {channel.description}
            </Text>
          </Pressable>
        ))}
      </View>
    </AppScreen>
  );
}

export function ChatChannelListScreen() {
  const { state } = useAuth();
  const router = useRouter();

  if (state.kind !== "authorized") return null;
  if (!isPhase3FixtureMode()) {
    return (
      <AppScreen testID="chat-contract-gated">
        <StatusNotice tone="warning">
          Standing chat is unavailable on mobile until server-maintained membership and message
          authorization are verified. Development preview data is not enabled in this build.
        </StatusNotice>
      </AppScreen>
    );
  }

  const fixture = createDevelopmentChatFixture(state.profile.id);
  return (
    <ChatChannelListScreenView
      channels={fixture.channels}
      onOpenChannel={(channelId) =>
        router.push({ pathname: "/messages/[channel-id]", params: { "channel-id": channelId } })
      }
    />
  );
}
