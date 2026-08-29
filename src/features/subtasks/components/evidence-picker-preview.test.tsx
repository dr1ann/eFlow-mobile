import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { EvidencePickerPreview } from "@/features/subtasks/components/evidence-picker-preview";

describe("EvidencePickerPreview", () => {
  it("shows sanitized metadata without displaying or uploading the local URI", async () => {
    const pickDocument = jest.fn(async () => ({
      uri: "file:///private/cache/report.pdf",
      displayName: "report.pdf",
      mimeType: "application/pdf",
      size: 1536
    }));
    const view = await render(
      <EvidencePickerPreview pickDocument={pickDocument} pickImage={async () => null} />
    );

    await fireEvent.press(view.getByLabelText("Choose document"));
    await waitFor(() => expect(view.getByText("report.pdf")).toBeTruthy());

    expect(view.getByText("application/pdf · 1.5 KB")).toBeTruthy();
    expect(view.queryByText("file:///private/cache/report.pdf")).toBeNull();
    expect(view.getByText(/not uploaded, submitted, logged, or persisted/i)).toBeTruthy();
  });

  it("treats picker cancellation as a normal no-selection result", async () => {
    const view = await render(
      <EvidencePickerPreview pickDocument={async () => null} pickImage={async () => null} />
    );

    await fireEvent.press(view.getByLabelText("Choose image"));
    await waitFor(() => expect(view.queryByTestId("selected-evidence-preview")).toBeNull());
    expect(view.queryByText(/could not be selected/i)).toBeNull();
  });

  it("redacts unexpected picker errors and allows another attempt", async () => {
    const pickDocument = jest.fn(async () => {
      throw new Error("file:///private/secret/report.pdf");
    });
    const view = await render(
      <EvidencePickerPreview pickDocument={pickDocument} pickImage={async () => null} />
    );

    await fireEvent.press(view.getByLabelText("Choose document"));
    await waitFor(() => expect(view.getByText(/could not be selected/i)).toBeTruthy());
    expect(view.queryByText(/private\/secret/)).toBeNull();
  });
});
