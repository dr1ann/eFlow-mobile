import { fireEvent, render } from "@testing-library/react-native";

import type { ChatChannelSummary } from "@/contracts/chat";
import { ChatChannelListScreenView } from "@/features/chat/screens/channel-list-screen";

const channel: ChatChannelSummary = {
  id: "11111111-1111-4111-8111-111111111111",
  kind: "organization",
  title: "Development organization channel",
  description: "Synthetic channel",
  unreadCount: 1
};

describe("ChatChannelListScreenView", () => {
  it("labels synthetic content and opens a selected development channel", async () => {
    const onOpenChannel = jest.fn();
    const view = await render(
      <ChatChannelListScreenView channels={[channel]} onOpenChannel={onOpenChannel} />
    );

    expect(view.getByText(/Development-only preview/i)).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open development chat Development organization channel/i));
    expect(onOpenChannel).toHaveBeenCalledWith(channel.id);
  });
});
