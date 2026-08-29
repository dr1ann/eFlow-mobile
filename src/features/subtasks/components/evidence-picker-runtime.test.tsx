import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { EvidencePickerPreview } from "@/features/subtasks/components/evidence-picker-preview";

jest.mock("expo-document-picker", () => {
  throw new Error("Cannot find native module 'ExpoDocumentPicker'");
});

jest.mock("expo-image-picker", () => {
  throw new Error("Cannot find native module 'ExponentImagePicker'");
});

describe("EvidencePickerPreview native runtime recovery", () => {
  it("renders before loading optional native modules and explains how to recover", async () => {
    const view = await render(<EvidencePickerPreview />);

    expect(view.getByLabelText("Choose document")).toBeTruthy();
    await fireEvent.press(view.getByLabelText("Choose document"));

    await waitFor(() =>
      expect(view.getByText(/runtime does not include the native picker/i)).toBeTruthy()
    );
    expect(view.queryByText(/ExpoDocumentPicker/)).toBeNull();
  });
});
