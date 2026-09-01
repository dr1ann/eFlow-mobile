import { fireEvent, render } from "@testing-library/react-native";

import { MoreScreen } from "./more-screen";

const mockPush = jest.fn();
const mockCan = jest.fn();

jest.mock("expo-router", () => ({
  ...jest.requireActual("expo-router"),
  useRouter: () => ({ push: mockPush })
}));

jest.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ can: mockCan })
}));

describe("MoreScreen", () => {
  beforeEach(() => {
    mockPush.mockReset();
    mockCan.mockReset();
  });

  it("shows only destinations permitted for the signed-in account", async () => {
    mockCan.mockImplementation((permission: string) => permission === "navigation.tasks");

    const view = await render(<MoreScreen />);

    expect(view.getByLabelText("Reviews")).toBeTruthy();
    expect(view.queryByLabelText("Notices")).toBeNull();
    expect(view.getByLabelText("Settings")).toBeTruthy();
  });

  it("opens the selected stack destination", async () => {
    mockCan.mockReturnValue(true);
    const view = await render(<MoreScreen />);

    await fireEvent.press(view.getByLabelText("Notices"));

    expect(mockPush).toHaveBeenCalledWith("/announcements");
  });
});
