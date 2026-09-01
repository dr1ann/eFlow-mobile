import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import { TaskDetailView } from "@/features/tasks/screens/task-detail-screen";

const task = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Prepare service report",
  status: "in_progress",
  description: "Compile metrics.",
  priority: "high",
  dueDate: "2026-08-30",
  deadline: null,
  percentComplete: 40,
  assignedTo: null,
  recommendationLeadId: null,
  assigneeName: "Task Lead",
  reviewerId: null,
  backupReviewerId: null,
  teamMemberIds: [],
  teamMemberNames: [],
  teamName: "Operations",
  dependencyIds: [],
  acceptanceCriteria: ["Figures are reconciled"],
  definitionOfDone: "Reviewer-ready report",
  feedback: null,
  projectId: null,
  projectTitle: "Citizen Services",
  tags: [],
  subtaskCount: 1,
  subtaskCompletedCount: 0,
  createdAt: null,
  updatedAt: null
} satisfies Task;

const subtask = {
  id: "22222222-2222-4222-8222-222222222222",
  taskId: task.id,
  title: "Collect source figures",
  status: "todo",
  percentComplete: 0,
  assignedTo: null,
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

describe("TaskDetailView", () => {
  it("renders requirements and opens a visible subtask", async () => {
    const onOpenSubtask = jest.fn();
    const view = await render(
      <TaskDetailView
        task={task}
        subtasks={[subtask]}
        subtasksLoading={false}
        subtasksError={false}
        onOpenSubtask={onOpenSubtask}
        onRetrySubtasks={jest.fn()}
      />
    );

    expect(view.getByText(/Figures are reconciled/)).toBeTruthy();
    expect(view.getByText("Reviewer-ready report")).toBeTruthy();
    expect(view.getByText(/Evidence remains private/i)).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open Collect source figures/));
    expect(onOpenSubtask).toHaveBeenCalledWith(subtask.id);
  });
});
