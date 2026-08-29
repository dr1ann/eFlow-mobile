import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
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

describe("SubtaskDetailView", () => {
  it("does not offer local evidence selection to an ineligible viewer", async () => {
    const onOpenTask = jest.fn();
    const view = await render(
      <SubtaskDetailView
        subtask={subtask}
        canPrepareEvidence={false}
        onOpenTask={onOpenTask}
      />
    );

    expect(view.getByText(/available only to an assigned contributor/i)).toBeTruthy();
    expect(view.queryByLabelText("Choose document")).toBeNull();
    await fireEvent.press(view.getByLabelText("Open parent task"));
    expect(onOpenTask).toHaveBeenCalledTimes(1);
  });
});
