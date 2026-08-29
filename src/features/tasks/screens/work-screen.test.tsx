import { fireEvent, render } from "@testing-library/react-native";

import type { Task } from "@/contracts/tasks";
import { WorkScreenView, flattenTaskFeed } from "@/features/tasks/screens/work-screen";

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
  projectId: null,
  projectTitle: "Citizen Services",
  tags: [],
  subtaskCount: 1,
  subtaskCompletedCount: 0,
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
    expect(empty.getByText("No tasks match this filter.")).toBeTruthy();
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
});
