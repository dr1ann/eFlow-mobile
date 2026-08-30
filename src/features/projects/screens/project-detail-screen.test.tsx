import { render } from "@testing-library/react-native";

import type { ProjectOverview } from "@/contracts/projects";
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

describe("ProjectDetailView", () => {
  it("renders an authorized project summary without presenting unsafe mutations", async () => {
    const view = await render(<ProjectDetailView project={project} />);

    expect(view.getByText("Records modernization")).toBeTruthy();
    expect(view.getByText("On hold · Medium priority")).toBeTruthy();
    expect(view.getByText("Aug 1, 2026")).toBeTruthy();
    expect(view.getByText(/project changes stay unavailable/i)).toBeTruthy();
    expect(view.queryByLabelText(/Edit project/i)).toBeNull();
  });
});
