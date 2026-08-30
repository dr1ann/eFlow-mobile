import { fireEvent, render } from "@testing-library/react-native";

import type { ProjectOverview } from "@/contracts/projects";
import {
  ProjectListScreenView,
  flattenProjectFeed
} from "@/features/projects/screens/project-list-screen";

const project = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Records modernization",
  description: "Digitize records.",
  status: "active",
  priority: "high",
  startDate: "2026-08-01",
  targetDate: "2026-09-01",
  programTitle: "Digital services",
  ownerId: "22222222-2222-4222-8222-222222222222",
  organizationId: "33333333-3333-4333-8333-333333333333",
  archivedAt: null,
  updatedAt: "2026-08-26T00:00:00+00:00"
} satisfies ProjectOverview;

const baseProps = {
  filter: "all" as const,
  search: "",
  isLoading: false,
  isRefreshing: false,
  isError: false,
  isPaused: false,
  hasNextPage: false,
  isFetchingNextPage: false,
  onFilterChange: jest.fn(),
  onSearchChange: jest.fn(),
  onRefresh: jest.fn(),
  onLoadMore: jest.fn(),
  onOpenProject: jest.fn()
};

describe("ProjectListScreenView", () => {
  beforeEach(() => jest.clearAllMocks());

  it("renders an authorized project and opens it from an accessible row", async () => {
    const onOpenProject = jest.fn();
    const view = await render(
      <ProjectListScreenView {...baseProps} projects={[project]} onOpenProject={onOpenProject} />
    );

    expect(view.getByText("Records modernization")).toBeTruthy();
    expect(view.getByText("High priority · Target Sep 1, 2026")).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open project Records modernization/));
    expect(onOpenProject).toHaveBeenCalledWith(project.id);
  });

  it("offers accessible search, filtering, empty, and retry states", async () => {
    const onSearchChange = jest.fn();
    const onFilterChange = jest.fn();
    const onRefresh = jest.fn();
    const empty = await render(
      <ProjectListScreenView
        {...baseProps}
        projects={[]}
        onSearchChange={onSearchChange}
        onFilterChange={onFilterChange}
      />
    );
    expect(empty.getByText("No projects match this filter.")).toBeTruthy();
    await fireEvent.changeText(empty.getByLabelText("Search projects"), "records");
    expect(onSearchChange).toHaveBeenCalledWith("records");
    await fireEvent.press(empty.getByLabelText("Filter projects by Active"));
    expect(onFilterChange).toHaveBeenCalledWith("active");
    await empty.unmount();

    const failed = await render(
      <ProjectListScreenView
        {...baseProps}
        projects={[]}
        isError
        onRefresh={onRefresh}
      />
    );
    expect(failed.getByText(/could not load projects/i)).toBeTruthy();
    await fireEvent.press(failed.getByLabelText("Try again"));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it("deduplicates rows received again after pagination or refresh", () => {
    expect(flattenProjectFeed([
      { items: [project], nextPage: 1 },
      { items: [{ ...project, priority: "medium" }], nextPage: null }
    ])).toEqual([{ ...project, priority: "medium" }]);
  });
});
