import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
import type { Task, TaskSubmission } from "@/contracts/tasks";
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
  linkedProjectId: null,
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

const submissions = [
  {
    id: "33333333-3333-4333-8333-333333333333",
    taskId: task.id,
    version: 2,
    note: "Corrected figures and attached reconciliation.",
    status: "approved",
    submitterId: "44444444-4444-4444-8444-444444444444",
    submitterName: "Task Lead",
    submittedAt: "2026-09-06T10:15:00.000Z",
    decidedAt: "2026-09-06T11:00:00.000Z",
    decidedBy: "55555555-5555-4555-8555-555555555555",
    decidedByName: "Department Head",
    decisionFeedback: "All corrections are complete."
  },
  {
    id: "66666666-6666-4666-8666-666666666666",
    taskId: task.id,
    version: 1,
    note: "Initial report.",
    status: "changes_requested",
    submitterId: "44444444-4444-4444-8444-444444444444",
    submitterName: "Task Lead",
    submittedAt: "2026-09-05T10:15:00.000Z",
    decidedAt: "2026-09-05T11:00:00.000Z",
    decidedBy: "55555555-5555-4555-8555-555555555555",
    decidedByName: "Department Head",
    decisionFeedback: "Please reconcile the figures."
  }
] satisfies TaskSubmission[];

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

  it("keeps reviewed attempts and feedback visible in version order", async () => {
    const view = await render(
      <TaskDetailView
        task={task}
        subtasks={[]}
        subtasksLoading={false}
        subtasksError={false}
        submissions={submissions}
        onOpenSubtask={jest.fn()}
        onRetrySubtasks={jest.fn()}
      />
    );

    expect(view.getByText("Corrected figures and attached reconciliation.")).toBeTruthy();
    expect(view.getByText("Please reconcile the figures.")).toBeTruthy();
    expect(view.getByText("Version 2 · Approved")).toBeTruthy();
    expect(view.getByText("Version 1 · Changes requested")).toBeTruthy();
    expect(view.getByText(/Approved by Department Head/)).toBeTruthy();
  });

  it("makes parent rework an explicit resume step before a new submission", async () => {
    const view = await render(
      <TaskDetailView
        task={{ ...task, status: "changes_requested" }}
        subtasks={[]}
        subtasksLoading={false}
        subtasksError={false}
        canStartTask
        canSubmitTask={false}
        onOpenSubtask={jest.fn()}
        onRetrySubtasks={jest.fn()}
        onStartTask={jest.fn()}
      />
    );

    expect(view.getByLabelText("Resume work")).toBeTruthy();
    expect(view.queryByLabelText("Submit task for review")).toBeNull();
  });

  it("uses the canonical linked project ID only when project navigation is available", async () => {
    const onOpenProject = jest.fn();
    const view = await render(
      <TaskDetailView
        task={{
          ...task,
          linkedProjectId: "77777777-7777-4777-8777-777777777777"
        }}
        subtasks={[]}
        subtasksLoading={false}
        subtasksError={false}
        canOpenProject
        onOpenProject={onOpenProject}
        onOpenSubtask={jest.fn()}
        onRetrySubtasks={jest.fn()}
      />
    );

    await fireEvent.press(view.getByLabelText("Open linked project"));
    expect(onOpenProject).toHaveBeenCalledTimes(1);
  });

  it("shows subtask planning only when the effective Task Lead has a verified planning capability", async () => {
    const onPlanSubtasks = jest.fn();
    const view = await render(
      <TaskDetailView
        task={task}
        subtasks={[]}
        subtasksLoading={false}
        subtasksError={false}
        canPlanSubtasks
        onPlanSubtasks={onPlanSubtasks}
        onOpenSubtask={jest.fn()}
        onRetrySubtasks={jest.fn()}
      />
    );

    await fireEvent.press(view.getByLabelText("Plan subtasks"));
    expect(onPlanSubtasks).toHaveBeenCalledTimes(1);
  });
});
