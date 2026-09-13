import { Alert } from "react-native";
import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask, SubtaskSubmission, SubtaskSubmissionAttachment } from "@/contracts/subtasks";
import { getCurrentSubtaskReviewSubmission } from "@/features/reviews/submission-selection";
import { SubtaskReviewView } from "@/features/reviews/screens/subtask-review-screen";

const subtask = {
  title: "Collect source figures"
} satisfies Pick<Subtask, "title">;

const currentSubmission = {
  id: "11111111-1111-4111-8111-111111111111",
  taskId: "22222222-2222-4222-8222-222222222222",
  subtaskId: "33333333-3333-4333-8333-333333333333",
  version: 2,
  note: "Added the corrected source ledger.",
  status: "pending",
  submitterId: "44444444-4444-4444-8444-444444444444",
  submitterName: "Contributor",
  reviewerId: "55555555-5555-4555-8555-555555555555",
  submittedAt: "2026-09-06T10:15:00.000Z",
  decidedAt: null,
  decidedBy: null,
  decidedByName: null,
  decisionFeedback: null
} satisfies SubtaskSubmission;

const attachment = {
  id: "66666666-6666-4666-8666-666666666666",
  submissionId: currentSubmission.id,
  taskId: currentSubmission.taskId,
  subtaskId: currentSubmission.subtaskId,
  fileName: "source-ledger.pdf",
  filePath: "private/current-source-ledger.pdf",
  fileSize: 2048,
  mimeType: "application/pdf",
  uploadedBy: currentSubmission.submitterId,
  createdAt: "2026-09-06T10:15:00.000Z"
} satisfies SubtaskSubmissionAttachment;

async function renderSubtaskReview(overrides: Partial<React.ComponentProps<typeof SubtaskReviewView>> = {}) {
  const defaults: React.ComponentProps<typeof SubtaskReviewView> = {
    subtask,
    submission: currentSubmission,
    attachments: [attachment],
    attachmentsLoading: false,
    attachmentsError: false,
    canOpenEvidence: true,
    canReview: true,
    decisionPending: false,
    decisionError: null,
    onRetryAttachments: jest.fn(),
    onDecide: jest.fn(),
    onBack: jest.fn()
  };
  const view = await render(<SubtaskReviewView {...defaults} {...overrides} />);
  return { ...view, props: { ...defaults, ...overrides } };
}

describe("SubtaskReviewView", () => {
  afterEach(() => jest.restoreAllMocks());

  it("renders review-ready subtask evidence metadata without exposing its path", async () => {
    const view = await renderSubtaskReview();

    expect(view.getByText("Added the corrected source ledger.")).toBeTruthy();
    expect(view.getByText("Contributor")).toBeTruthy();
    expect(view.getByText("source-ledger.pdf")).toBeTruthy();
    expect(view.getByText("application/pdf · 2.0 KB")).toBeTruthy();
    expect(view.queryByText("private/current-source-ledger.pdf")).toBeNull();
  });

  it("denies an unresolved reviewer before showing a decision form", async () => {
    const view = await renderSubtaskReview({ canReview: false });

    expect(view.getByText("You are not the resolved reviewer for this submission.")).toBeTruthy();
    expect(view.queryByLabelText("Review feedback")).toBeNull();
    expect(view.queryByLabelText("Approve subtask")).toBeNull();
  });

  it("sends requested-change feedback through the confirmation action", async () => {
    const onDecide = jest.fn();
    const alert = jest.spyOn(Alert, "alert").mockImplementation(() => undefined);
    const view = await renderSubtaskReview({ onDecide });

    await fireEvent.changeText(view.getByLabelText("Review feedback"), "Please add the missing page.");
    await fireEvent.press(view.getByLabelText("Request changes"));

    const buttons = alert.mock.calls[0]?.[2] ?? [];
    buttons.find((button) => button.text === "Request changes")?.onPress?.();
    expect(onDecide).toHaveBeenCalledWith(false, "Please add the missing page.");
  });

  it("uses the server's latest submission id instead of a stale pending row", () => {
    const historicPending = { ...currentSubmission, id: "77777777-7777-4777-8777-777777777777", version: 1 };
    const latestApproved = {
      ...currentSubmission,
      status: "approved" as const,
      decisionFeedback: "Accepted",
      decidedAt: "2026-09-06T11:00:00.000Z"
    };

    expect(getCurrentSubtaskReviewSubmission(
      { latestSubmissionId: latestApproved.id },
      [historicPending, latestApproved]
    )).toBeUndefined();
    expect(getCurrentSubtaskReviewSubmission(
      { latestSubmissionId: currentSubmission.id },
      [historicPending, currentSubmission]
    )).toEqual(currentSubmission);
  });
});
