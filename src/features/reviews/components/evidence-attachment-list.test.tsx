import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { EvidenceAttachmentList } from "@/features/reviews/components/evidence-attachment-list";

const attachments = [
  {
    id: "11111111-1111-4111-8111-111111111111",
    fileName: "corrected-report.pdf",
    filePath: "private/current-attempt.pdf",
    fileSize: 1536,
    mimeType: "application/pdf"
  },
  {
    id: "22222222-2222-4222-8222-222222222222",
    fileName: "supporting-photo.jpg",
    filePath: "private/current-photo.jpg",
    fileSize: 512,
    mimeType: "image/jpeg"
  }
];

describe("EvidenceAttachmentList", () => {
  it("renders only supplied attempt metadata and opens a file without rendering its private path", async () => {
    const openEvidence = jest.fn(async () => undefined);
    const view = await render(
      <EvidenceAttachmentList
        attachments={[attachments[0]!]}
        isLoading={false}
        isError={false}
        canOpen
        emptyMessage="No evidence"
        openEvidence={openEvidence}
      />
    );

    expect(view.getByText("corrected-report.pdf")).toBeTruthy();
    expect(view.getByText("application/pdf · 1.5 KB")).toBeTruthy();
    expect(view.queryByText("supporting-photo.jpg")).toBeNull();
    expect(view.queryByText("private/current-attempt.pdf")).toBeNull();

    await fireEvent.press(view.getByLabelText("Open corrected-report.pdf"));
    await waitFor(() => expect(openEvidence).toHaveBeenCalledWith("private/current-attempt.pdf"));
  });

  it("keeps file opening retryable and redacts a failed signed-link open", async () => {
    const openEvidence = jest.fn(async () => {
      throw new Error("https://private.example.test/signed-token");
    });
    const view = await render(
      <EvidenceAttachmentList
        attachments={[attachments[0]!]}
        isLoading={false}
        isError={false}
        canOpen
        emptyMessage="No evidence"
        openEvidence={openEvidence}
      />
    );

    await fireEvent.press(view.getByLabelText("Open corrected-report.pdf"));
    await waitFor(() => expect(view.getByText("We could not open this evidence file. Try again.")).toBeTruthy());
    expect(view.queryByText(/signed-token/)).toBeNull();

    await fireEvent.press(view.getByLabelText("Open corrected-report.pdf"));
    await waitFor(() => expect(openEvidence).toHaveBeenCalledTimes(2));
  });

  it("keeps other evidence actions disabled while one file is opening", async () => {
    let resolveOpening: (() => void) | undefined;
    const openEvidence = jest.fn(() => new Promise<void>((resolve) => {
      resolveOpening = resolve;
    }));
    const view = await render(
      <EvidenceAttachmentList
        attachments={attachments}
        isLoading={false}
        isError={false}
        canOpen
        emptyMessage="No evidence"
        openEvidence={openEvidence}
      />
    );

    fireEvent.press(view.getByLabelText("Open corrected-report.pdf"));
    await waitFor(() => expect(
      view.getByLabelText("Open supporting-photo.jpg").props.accessibilityState.disabled
    ).toBe(true));
    resolveOpening?.();
    await waitFor(() => expect(view.getByLabelText("Open supporting-photo.jpg").props.accessibilityState.disabled).toBe(false));
  });
});
