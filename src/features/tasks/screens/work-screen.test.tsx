import { fireEvent, render } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import {
  SubtaskWorkScreenView,
  WorkScreenView,
  filterTasksForDeadline,
  flattenSubtaskFeed,
  flattenTaskFeed
} from "@/features/tasks/screens/work-screen";

const task: Task = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Prepare service report",
  status: "in_progress",
  description: "Compile the monthly service metrics.",
  priority: "high",
  dueDate: "2026-08-30",
  deadline: null,
  percentComplete: 40,
  assignedTo: "22222222-2222-4222-8222-222222222222",
  recommendationLeadId: null,
  assigneeName: "Employee",
  reviewerId: null,
  backupReviewerId: null,
  teamMemberIds: [],
  teamMemberNames: [],
  teamName: null,
  dependencyIds: [],
  acceptanceCriteria: [],
  definitionOfDone: null,
  feedback: null,
  linkedProjectId: null,
  projectId: null,
  projectTitle: "Citizen Services",
  tags: [],
  subtaskCount: 1,
  subtaskCompletedCount: 0,
  createdAt: null,
  updatedAt: null
};

const subtask: Subtask = {
  id: "33333333-3333-4333-8333-333333333333",
  taskId: task.id,
  title: "Collect service figures",
  status: "in_progress",
  percentComplete: 50,
  assignedTo: null,
  assignedToIds: ["44444444-4444-4444-8444-444444444444"],
  reviewerId: null,
  dueDate: "2026-08-31",
  position: 1,
  isCompleted: false,
  latestSubmissionId: null,
  source: null,
  createdAt: null,
  updatedAt: null
};

const baseProps = {
  filter: "active" as const,
  isLoading: false,
  isRefreshing: false,
  isError: false,
  isPaused: false,
  hasNextPage: false,
  isFetchingNextPage: false,
  onFilterChange: jest.fn(),
  onRefresh: jest.fn(),
  onLoadMore: jest.fn(),
  onOpenTask: jest.fn()
};

describe("WorkScreenView", () => {
  beforeEach(() => jest.clearAllMocks());

  it("renders an authorized task and opens it from an accessible row", async () => {
    const onOpenTask = jest.fn();
    const view = await render(
      <WorkScreenView {...baseProps} tasks={[task]} onOpenTask={onOpenTask} />
    );

    expect(view.getByText("Prepare service report")).toBeTruthy();
    expect(view.getByText("In progress · Aug 30, 2026")).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open Prepare service report/));
    expect(onOpenTask).toHaveBeenCalledWith(task.id);
  });

  it("shows empty, retry, and filter behavior without leaking server details", async () => {
    const onFilterChange = jest.fn();
    const onRefresh = jest.fn();
    const empty = await render(
      <WorkScreenView
        {...baseProps}
        tasks={[]}
        onFilterChange={onFilterChange}
      />
    );
    expect(empty.getByText("No tasks match these filters.")).toBeTruthy();
    await fireEvent.press(empty.getByLabelText("Filter tasks by Waiting"));
    expect(onFilterChange).toHaveBeenCalledWith("waiting");
    await empty.unmount();

    const failed = await render(
      <WorkScreenView
        {...baseProps}
        tasks={[]}
        isError
        onRefresh={onRefresh}
      />
    );
    expect(failed.getByText(/could not load your tasks/i)).toBeTruthy();
    await fireEvent.press(failed.getByLabelText("Try again"));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it("deduplicates rows received again after pagination or refresh", () => {
    expect(flattenTaskFeed([
      { items: [task], nextPage: 1 },
      { items: [{ ...task, percentComplete: 60 }], nextPage: null }
    ])).toEqual([{ ...task, percentComplete: 60 }]);
  });

  it("keeps later authorized pages reachable when a local deadline filter has no loaded match", async () => {
    const onLoadMore = jest.fn();
    const view = await render(
      <WorkScreenView
        {...baseProps}
        tasks={[]}
        hasNextPage
        deadlineFilter="overdue"
        onLoadMore={onLoadMore}
      />
    );

    expect(view.getByText(/No matching tasks are loaded yet/i)).toBeTruthy();
    await fireEvent.press(view.getByLabelText("Load more tasks"));
    expect(onLoadMore).toHaveBeenCalledTimes(1);
  });

  it("exposes leading and subtask work views and their accessible controls", async () => {
    const onScopeChange = jest.fn();
    const onDeadlineFilterChange = jest.fn();
    const taskView = await render(
      <WorkScreenView
        {...baseProps}
        tasks={[task]}
        scope="leading"
        onScopeChange={onScopeChange}
        onDeadlineFilterChange={onDeadlineFilterChange}
      />
    );

    expect(taskView.getByText("Work I am leading")).toBeTruthy();
    await fireEvent.press(taskView.getByLabelText("Show My Subtasks"));
    expect(onScopeChange).toHaveBeenCalledWith("subtasks");
    await fireEvent.press(taskView.getByLabelText("Show overdue work"));
    expect(onDeadlineFilterChange).toHaveBeenCalledWith("overdue");
    await taskView.unmount();

    const onOpenSubtask = jest.fn();
    const subtaskView = await render(
      <SubtaskWorkScreenView
        subtasks={[subtask]}
        filter="active"
        deadlineFilter="all"
        isLoading={false}
        isRefreshing={false}
        isError={false}
        isPaused={false}
        hasNextPage={false}
        isFetchingNextPage={false}
        onFilterChange={jest.fn()}
        onDeadlineFilterChange={jest.fn()}
        onScopeChange={jest.fn()}
        onRefresh={jest.fn()}
        onLoadMore={jest.fn()}
        onOpenSubtask={onOpenSubtask}
      />
    );

    expect(subtaskView.getByText("My subtasks")).toBeTruthy();
    await fireEvent.press(subtaskView.getByLabelText(/Open Collect service figures/));
    expect(onOpenSubtask).toHaveBeenCalledWith(subtask.id);
  });

  it("deduplicates subtask pages and applies a local, loaded-item deadline filter", () => {
    const updated = { ...subtask, percentComplete: 75 };
    expect(flattenSubtaskFeed([
      { items: [subtask], nextPage: 1 },
      { items: [updated], nextPage: null }
    ])).toEqual([updated]);
    expect(filterTasksForDeadline([task], "overdue", new Date(2026, 8, 1, 8, 0, 0))).toEqual([task]);
  });
});
