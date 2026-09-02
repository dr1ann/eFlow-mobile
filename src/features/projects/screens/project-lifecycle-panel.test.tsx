import { fireEvent, render } from "@testing-library/react-native";

import type { ProjectCompletionReadiness } from "@/features/projects/api/project-workflow-api";
import { ProjectLifecycleView } from "@/features/projects/screens/project-lifecycle-panel";
import type { ProjectOverview } from "@/contracts/projects";

const project: ProjectOverview = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Records modernization",
  description: "Digitize records.",
  status: "active",
  priority: "medium",
  startDate: null,
  targetDate: null,
  programTitle: null,
  ownerId: null,
  organizationId: null,
  archivedAt: null,
  updatedAt: "2026-09-01T00:00:00+00:00"
};

const ready: ProjectCompletionReadiness = {
  projectId: project.id,
  title: project.title,
  status: "active",
  canComplete: true,
  blockers: []
};

describe("ProjectLifecycleView", () => {
  it("does not allow completion while server-calculated blockers remain", async () => {
    const onComplete = jest.fn();
    const view = await render(
      <ProjectLifecycleView
        project={project}
        readiness={{
          ...ready,
          canComplete: false,
          blockers: [
            {
              kind: "financial",
              title: "Financial clearance",
              detail: "Financial clearance must be resolved on the web before this project can be completed.",
              taskId: null
            }
          ]
        }}
        loading={false}
        error={null}
        completionNote=""
        archiveReason=""
        completing={false}
        archiving={false}
        mutationError={null}
        onCompletionNoteChange={jest.fn()}
        onArchiveReasonChange={jest.fn()}
        onRefresh={jest.fn()}
        onComplete={onComplete}
        onArchive={jest.fn()}
      />
    );

    expect(view.getByText("Financial clearance")).toBeTruthy();
    expect(view.getByText(/resolved on the web/i)).toBeTruthy();
    expect(view.getByLabelText("Mark project complete").props.accessibilityState.disabled).toBe(true);
    await fireEvent.press(view.getByLabelText("Mark project complete"));
    expect(onComplete).not.toHaveBeenCalled();
  });

  it("allows an eligible project to be completed and completed projects to be archived", async () => {
    const onComplete = jest.fn();
    const onArchive = jest.fn();
    const readyView = await render(
      <ProjectLifecycleView
        project={project}
        readiness={ready}
        loading={false}
        error={null}
        completionNote="Closeout confirmed"
        archiveReason=""
        completing={false}
        archiving={false}
        mutationError={null}
        onCompletionNoteChange={jest.fn()}
        onArchiveReasonChange={jest.fn()}
        onRefresh={jest.fn()}
        onComplete={onComplete}
        onArchive={onArchive}
      />
    );

    await fireEvent.press(readyView.getByLabelText("Mark project complete"));
    expect(onComplete).toHaveBeenCalledTimes(1);

    const completedView = await render(
      <ProjectLifecycleView
        {...{
          project: { ...project, status: "completed" as const },
          readiness: { ...ready, status: "completed" as const },
          loading: false,
          error: null,
          completionNote: "",
          archiveReason: "Retention complete",
          completing: false,
          archiving: false,
          mutationError: null,
          onCompletionNoteChange: jest.fn(),
          onArchiveReasonChange: jest.fn(),
          onRefresh: jest.fn(),
          onComplete: jest.fn(),
          onArchive
        }}
      />
    );
    await fireEvent.press(completedView.getByLabelText("Archive project"));
    expect(onArchive).toHaveBeenCalledTimes(1);
  });
});
