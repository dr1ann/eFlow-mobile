import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask, SubtaskProgressUpdate, SubtaskSubmission } from "@/contracts/subtasks";
import { SubtaskDetailView } from "@/features/subtasks/screens/subtask-detail-screen";

const subtask = {
  id: "22222222-2222-4222-8222-222222222222",
  taskId: "11111111-1111-4111-8111-111111111111",
  title: "Collect source figures",
  status: "in_progress",
  percentComplete: 25,
  assignedTo: "33333333-3333-4333-8333-333333333333",
  assignedToIds: [],
  reviewerId: null,
  dueDate: "2026-08-29",
  position: 1,
  isCompleted: false,
  latestSubmissionId: null,
  source: null,
  createdAt: null,
  updatedAt: null
} satisfies Subtask;

const submissions = [
  {
    id: "33333333-3333-4333-8333-333333333333",
    taskId: subtask.taskId,
    subtaskId: subtask.id,
    version: 2,
    note: "Updated source figures.",
    status: "approved",
    submitterId: subtask.assignedTo!,
    submitterName: "Contributor",
    reviewerId: "44444444-4444-4444-8444-444444444444",
    submittedAt: "2026-09-06T10:15:00.000Z",
    decidedAt: "2026-09-06T11:00:00.000Z",
    decidedBy: "44444444-4444-4444-8444-444444444444",
    decidedByName: "Task Lead",
    decisionFeedback: "Evidence now matches the source."
  },
  {
    id: "55555555-5555-4555-8555-555555555555",
    taskId: subtask.taskId,
    subtaskId: subtask.id,
    version: 1,
    note: "Initial source figures.",
    status: "changes_requested",
    submitterId: subtask.assignedTo!,
    submitterName: "Contributor",
    reviewerId: "44444444-4444-4444-8444-444444444444",
    submittedAt: "2026-09-05T10:15:00.000Z",
    decidedAt: "2026-09-05T11:00:00.000Z",
    decidedBy: "44444444-4444-4444-8444-444444444444",
    decidedByName: "Task Lead",
    decisionFeedback: "Please include the source ledger."
  }
] satisfies SubtaskSubmission[];

const progressUpdates = [{
  id: "66666666-6666-4666-8666-666666666666",
  taskId: subtask.taskId,
  subtaskId: subtask.id,
  authorId: subtask.assignedTo!,
  authorName: "Contributor",
  percentComplete: 50,
  blockerCategory: "dependency",
  blocker: "Waiting for the source ledger.",
  nextStep: "Reconcile the corrected figures.",
  note: "Initial reconciliation is complete.",
  attachmentPath: "private/path/never-rendered.pdf",
  attachmentName: "ledger.pdf",
  createdAt: "2026-09-05T09:00:00.000Z"
}] satisfies SubtaskProgressUpdate[];

describe("SubtaskDetailView", () => {
  it("shows versioned feedback and progress without exposing a private file path", async () => {
    const onOpenTask = jest.fn();
    const view = await render(
      <SubtaskDetailView
        subtask={subtask}
        submissions={submissions}
        progressUpdates={progressUpdates}
        onOpenTask={onOpenTask}
      />
    );

    expect(view.getByText("Updated source figures.")).toBeTruthy();
    expect(view.getByText("Please include the source ledger.")).toBeTruthy();
    expect(view.getByText("Initial reconciliation is complete.")).toBeTruthy();
    expect(view.getByText("Waiting for the source ledger.")).toBeTruthy();
    expect(view.getByText("ledger.pdf")).toBeTruthy();
    expect(view.queryByLabelText("Choose document")).toBeNull();
    expect(view.queryByText("private/path/never-rendered.pdf")).toBeNull();
    await fireEvent.press(view.getByLabelText("Open parent task"));
    expect(onOpenTask).toHaveBeenCalledTimes(1);
  });

  it("labels a corrected subtask attempt as a resubmission", async () => {
    const view = await render(
      <SubtaskDetailView
        subtask={{ ...subtask, status: "changes_requested" }}
        canSubmit
        onOpenTask={jest.fn()}
        onSubmit={jest.fn()}
      />
    );

    expect(view.getByLabelText("Resubmit for review")).toBeTruthy();
  });
});
