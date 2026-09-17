import { fireEvent, render } from "@testing-library/react-native";

import type { ProjectOverview } from "@/contracts/projects";
import type { Task } from "@/contracts/tasks";
import { ProjectDetailView } from "@/features/projects/screens/project-detail-screen";

const project = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Records modernization",
  description: "Digitize records.",
  status: "on_hold",
  priority: "medium",
  startDate: "2026-08-01",
  targetDate: "2026-09-01",
  programTitle: null,
  ownerId: null,
  organizationId: null,
  archivedAt: null,
  updatedAt: "2026-08-26T00:00:00+00:00"
} satisfies ProjectOverview;

const task = {
  id: "22222222-2222-4222-8222-222222222222",
  title: "Digitize archived records",
  status: "in_progress",
  description: null,
  priority: "high",
  dueDate: "2026-09-01",
  deadline: null,
  percentComplete: 40,
  assignedTo: null,
  recommendationLeadId: null,
  assigneeName: null,
  reviewerId: null,
  backupReviewerId: null,
  teamMemberIds: [],
  teamMemberNames: [],
  teamName: null,
  dependencyIds: [],
  acceptanceCriteria: [],
  definitionOfDone: null,
  feedback: null,
  linkedProjectId: project.id,
  projectId: "legacy-proposal-hierarchy",
  projectTitle: project.title,
  tags: [],
  subtaskCount: null,
  subtaskCompletedCount: null,
  createdAt: null,
  updatedAt: null
} satisfies Task;

describe("ProjectDetailView", () => {
  it("renders an authorized project summary without presenting unsafe mutations", async () => {
    const view = await render(<ProjectDetailView project={project} />);

    expect(view.getByText("Records modernization")).toBeTruthy();
    expect(view.getByText("On hold · Medium priority")).toBeTruthy();
    expect(view.getByText("Aug 1, 2026")).toBeTruthy();
    expect(view.getByText(/project changes stay unavailable/i)).toBeTruthy();
    expect(view.queryByLabelText(/Edit project/i)).toBeNull();
  });

  it("shows only authorized linked tasks and opens each route through a fresh task read", async () => {
    const onOpenTask = jest.fn();
    const view = await render(
      <ProjectDetailView
        project={project}
        linkedTasks={[task]}
        canViewLinkedTasks
        onOpenTask={onOpenTask}
      />
    );

    expect(view.getByText("Related work")).toBeTruthy();
    expect(view.getByText("Digitize archived records")).toBeTruthy();
    await fireEvent.press(view.getByLabelText(/Open Digitize archived records/));
    expect(onOpenTask).toHaveBeenCalledWith(task.id);
  });

  it("keeps unavailable related work generic and does not render records without task navigation access", async () => {
    const unavailable = await render(
      <ProjectDetailView project={project} canViewLinkedTasks linkedTasksError onRetryLinkedTasks={jest.fn()} />
    );
    expect(unavailable.getByText(/could not load related work/i)).toBeTruthy();
    await unavailable.unmount();

    const denied = await render(<ProjectDetailView project={project} linkedTasks={[task]} />);
    expect(denied.getByText(/Related work is unavailable for this mobile access/i)).toBeTruthy();
    expect(denied.queryByText("Digitize archived records")).toBeNull();
  });
});
