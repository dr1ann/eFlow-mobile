import { Alert } from "react-native";
import { fireEvent, render, waitFor } from "@testing-library/react-native";

import type { Task, TaskAttachment, TaskSubmission } from "@/contracts/tasks";
import { getCurrentTaskReviewSubmission } from "@/features/reviews/submission-selection";
import { TaskReviewView } from "@/features/reviews/screens/task-review-screen";

const task = {
  title: "Prepare service report",
  reviewerId: "22222222-2222-4222-8222-222222222222",
  backupReviewerId: "33333333-3333-4333-8333-333333333333"
} satisfies Pick<Task, "title" | "reviewerId" | "backupReviewerId">;

const currentSubmission = {
  id: "44444444-4444-4444-8444-444444444444",
  taskId: "11111111-1111-4111-8111-111111111111",
  version: 2,
  note: "Corrected the reconciliation totals.",
  status: "pending",
  submitterId: "55555555-5555-4555-8555-555555555555",
  submitterName: "Task Lead",
  submittedAt: "2026-09-06T10:15:00.000Z",
  decidedAt: null,
  decidedBy: null,
  decidedByName: null,
  decisionFeedback: null
} satisfies TaskSubmission;

const attachment = {
  id: "66666666-6666-4666-8666-666666666666",
  taskId: currentSubmission.taskId,
  submissionId: currentSubmission.id,
  fileName: "corrected-report.pdf",
  filePath: "private/current-attempt.pdf",
  fileSize: 1536,
  mimeType: "application/pdf",
  uploadedBy: currentSubmission.submitterId,
  uploadedAt: "2026-09-06T10:15:00.000Z"
} satisfies TaskAttachment;

async function renderTaskReview(overrides: Partial<React.ComponentProps<typeof TaskReviewView>> = {}) {
  const defaults: React.ComponentProps<typeof TaskReviewView> = {
    task,
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
  const view = await render(<TaskReviewView {...defaults} {...overrides} />);
  return { ...view, props: { ...defaults, ...overrides } };
}

describe("TaskReviewView", () => {
  afterEach(() => jest.restoreAllMocks());

  it("shows the selected attempt's note, author, time, status, and only its metadata", async () => {
    const view = await renderTaskReview();

    expect(view.getByText("Corrected the reconciliation totals.")).toBeTruthy();
    expect(view.getByText("Task Lead")).toBeTruthy();
    expect(view.getByText("Sep 6, 2026 · 10:15 UTC")).toBeTruthy();
    expect(view.getByText("Awaiting review")).toBeTruthy();
    expect(view.getByText("corrected-report.pdf")).toBeTruthy();
    expect(view.queryByText("private/current-attempt.pdf")).toBeNull();
  });

  it("shows an explicit empty parent-evidence state and retries an evidence read failure", async () => {
    const onRetryAttachments = jest.fn();
    const empty = await renderTaskReview({ attachments: [], onRetryAttachments });
    expect(empty.getByText("No evidence was attached to this parent task submission.")).toBeTruthy();

    const failed = await renderTaskReview({ attachmentsError: true, onRetryAttachments });
    await fireEvent.press(failed.getByLabelText("Retry attached evidence"));
    expect(onRetryAttachments).toHaveBeenCalledTimes(1);
  });

  it("requires feedback, sends it only after confirmation, and locks all decision controls while pending", async () => {
    const onDecide = jest.fn();
    const alert = jest.spyOn(Alert, "alert").mockImplementation(() => undefined);
    const view = await renderTaskReview({ onDecide });

    expect(view.getByLabelText("Request changes").props.accessibilityState.disabled).toBe(true);
    await fireEvent.changeText(view.getByLabelText("Review feedback"), "Please attach the source ledger.");
    await waitFor(() => expect(
      view.getByLabelText("Request changes").props.accessibilityState.disabled
    ).toBe(false));
    await fireEvent.press(view.getByLabelText("Request changes"));

    const buttons = alert.mock.calls[0]?.[2] ?? [];
    buttons.find((button) => button.text === "Request changes")?.onPress?.();
    expect(onDecide).toHaveBeenCalledWith(false, "Please attach the source ledger.");

    await view.rerender(
      <TaskReviewView
        {...view.props}
        decisionPending
      />
    );
    await waitFor(() => expect(view.getByLabelText("Approve task").props.accessibilityState.disabled).toBe(true));
    expect(view.getByLabelText("Request changes").props.accessibilityState.disabled).toBe(true);
    expect(view.getByLabelText("Review feedback").props.editable).toBe(false);
  });

  it("does not treat an older pending attempt as the current review", () => {
    const olderPending = { ...currentSubmission, id: "77777777-7777-4777-8777-777777777777", version: 1 };
    const latestApproved = {
      ...currentSubmission,
      status: "approved" as const,
      version: 2,
      decisionFeedback: "Accepted",
      decidedAt: "2026-09-06T11:00:00.000Z"
    };

    expect(getCurrentTaskReviewSubmission([latestApproved, olderPending])).toBeUndefined();
    expect(getCurrentTaskReviewSubmission([currentSubmission, olderPending])).toEqual(currentSubmission);
  });
});
