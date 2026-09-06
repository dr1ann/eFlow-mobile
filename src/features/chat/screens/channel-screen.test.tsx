import { fireEvent, render } from "@testing-library/react-native";

import type { ChatChannelSummary, ChatMessage } from "@/contracts/chat";
import { ChatChannelScreenView } from "@/features/chat/screens/channel-screen";

const channel: ChatChannelSummary = {
  id: "11111111-1111-4111-8111-111111111111",
  kind: "task",
  title: "Development task channel",
  description: "Synthetic channel",
  unreadCount: 0
};
const message: ChatMessage = {
  id: "22222222-2222-4222-8222-222222222222",
  clientRequestKey: null,
  channelId: channel.id,
  authorId: "33333333-3333-4333-8333-333333333333",
  authorLabel: "You",
  body: "Local preview message",
  createdAt: "2026-09-03T09:00:00.000Z",
  delivery: "sent"
};

describe("ChatChannelScreenView", () => {
  it("renders the local-only warning and validates compose interaction through accessible controls", async () => {
    const onDraftChange = jest.fn();
    const onSend = jest.fn();
    const view = await render(
      <ChatChannelScreenView
        channel={channel}
        messages={[message]}
        draft="Test reply"
        error="Enter a message before sending."
        onDraftChange={onDraftChange}
        onSend={onSend}
      />
    );

    expect(view.getByText(/does not send a chat message/i)).toBeTruthy();
    expect(view.getByText("Local preview message")).toBeTruthy();
    await fireEvent.changeText(view.getByLabelText("Development message"), "Another test reply");
    await fireEvent.press(view.getByLabelText("Add local test message"));
    expect(onDraftChange).toHaveBeenCalledWith("Another test reply");
    expect(onSend).toHaveBeenCalledTimes(1);
  });
});
