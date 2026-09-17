import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import {
  EMPTY_SUBTASK_PLANNING_FORM,
  type SubtaskPlanningCandidate
} from "@/features/subtasks/subtask-planning";
import {
  SubtaskPlanningView,
  type SubtaskPlanningCapabilities,
  type SubtaskPlanningViewProps
} from "@/features/subtasks/screens/subtask-planning-screen";

const ids = {
  task: "11111111-1111-4111-8111-111111111111",
  lead: "22222222-2222-4222-8222-222222222222",
  contributor: "33333333-3333-4333-8333-333333333333",
  subtask: "44444444-4444-4444-8444-444444444444"
};

const task: Task = {
  id: ids.task,
  title: "Community records update",
  status: "todo",
  description: null,
  priority: "high",
  dueDate: "2026-10-20",
  deadline: "2026-10-20",
  percentComplete: 0,
  assignedTo: ids.lead,
  recommendationLeadId: null,
  assigneeName: "Task Lead",
  reviewerId: null,
  backupReviewerId: null,
  teamMemberIds: [ids.lead, ids.contributor],
  teamMemberNames: ["Task Lead", "Contributor"],
  teamName: "Records team",
  dependencyIds: [],
  acceptanceCriteria: [],
  definitionOfDone: null,
  feedback: null,
  linkedProjectId: null,
  projectId: null,
  projectTitle: null,
  tags: [],
  subtaskCount: null,
  subtaskCompletedCount: null,
  createdAt: null,
  updatedAt: null
};

const subtask: Subtask = {
  id: ids.subtask,
  taskId: ids.task,
  title: "Prepare source records",
  status: "todo",
  percentComplete: 0,
  assignedTo: ids.contributor,
  assignedToIds: [ids.contributor],
  reviewerId: null,
  dueDate: "2026-10-10",
  position: 0,
  isStandalone: false,
  isCompleted: false,
  latestSubmissionId: null,
  source: "manual",
  createdAt: null,
  updatedAt: null
};

const candidates: readonly SubtaskPlanningCandidate[] = [
  { id: ids.lead, label: "Task Lead" },
  { id: ids.contributor, label: "Contributor" }
];

const enabledCapabilities: SubtaskPlanningCapabilities = {
  create: true,
  assign: true,
  schedule: true,
  reorder: true,
  executionRules: true
};

function props(overrides: Partial<SubtaskPlanningViewProps> = {}): SubtaskPlanningViewProps {
  return {
    task,
    subtasks: [subtask],
    candidates,
    values: EMPTY_SUBTASK_PLANNING_FORM,
    errors: {},
    capabilities: enabledCapabilities,
    isPending: false,
    mutationError: null,
    selectedSubtaskId: null,
    rescheduleDate: "",
    rescheduleReason: "",
    rescheduleError: null,
    onChange: jest.fn(),
    onCreate: jest.fn(),
    onAssign: jest.fn(),
    onSetExecutionMode: jest.fn(),
    onMove: jest.fn(),
    onSelectSchedule: jest.fn(),
    onRescheduleDateChange: jest.fn(),
    onRescheduleReasonChange: jest.fn(),
    onSaveSchedule: jest.fn(),
    ...overrides
  };
}

describe("SubtaskPlanningView", () => {
  it("offers accessible contributor and execution-mode choices before creating a new subtask", async () => {
    const viewProps = props();
    const view = await render(<SubtaskPlanningView {...viewProps} />);

    await fireEvent.changeText(view.getByLabelText("Subtask title"), "Digitize registers");
    await fireEvent.press(view.getByLabelText("Contributor"));
    await fireEvent.press(view.getByLabelText("Standalone"));
    await fireEvent.press(view.getByLabelText("Create subtask"));

    expect(viewProps.onChange).toHaveBeenCalledWith("title", "Digitize registers");
    expect(viewProps.onChange).toHaveBeenCalledWith("assigneeId", ids.contributor);
    expect(viewProps.onChange).toHaveBeenCalledWith("executionMode", "standalone");
    expect(viewProps.onCreate).toHaveBeenCalledTimes(1);
    expect(view.getAllByText(/Sequential/).length).toBeGreaterThan(0);
  });

  it("keeps structural actions out of a live screen until their individual capabilities are enabled", async () => {
    const view = await render(
      <SubtaskPlanningView
        {...props({
          capabilities: {
            create: false,
            assign: false,
            schedule: false,
            reorder: false,
            executionRules: false
          }
        })}
      />
    );

    expect(view.queryByLabelText("Create subtask")).toBeNull();
    expect(view.queryByLabelText("Assign to Task Lead")).toBeNull();
    expect(view.getByText(/remain unavailable/i)).toBeTruthy();
  });

  it("does not offer mutable controls for started work", async () => {
    const view = await render(
      <SubtaskPlanningView
        {...props({ subtasks: [{ ...subtask, status: "in_progress", percentComplete: 10 }] })}
      />
    );

    expect(view.getByText(/keeps its existing planning structure/i)).toBeTruthy();
    expect(view.queryByLabelText("Make standalone")).toBeNull();
  });
});
