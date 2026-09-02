import { invalidateProjectWorkflow } from "@/features/projects/use-project-workflow";

describe("project workflow cache invalidation", () => {
  it("refreshes project, related work, review, and notification surfaces after a lifecycle mutation", async () => {
    const invalidateQueries = jest.fn(async () => undefined);
    const projectId = "11111111-1111-4111-8111-111111111111";

    await invalidateProjectWorkflow({ invalidateQueries }, projectId);

    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["projects", "feed"] });
    expect(invalidateQueries).toHaveBeenCalledWith({
      queryKey: ["projects", "detail", projectId]
    });
    expect(invalidateQueries).toHaveBeenCalledWith({
      queryKey: ["projects", "completion-readiness", projectId]
    });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["tasks"] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["reviews"] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["notifications"] });
  });
});
