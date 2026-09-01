import {
  invalidateSubtaskWorkflow,
  invalidateTaskWorkflow
} from "@/features/workflow/cache-invalidation";

const taskId = "11111111-1111-4111-8111-111111111111";
const subtaskId = "22222222-2222-4222-8222-222222222222";

describe("Phase 1 workflow cache invalidation", () => {
  it("refreshes the affected task, review, notification, and child surfaces", async () => {
    const invalidateQueries = jest.fn(async () => undefined);
    await invalidateTaskWorkflow({ invalidateQueries }, taskId);

    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["tasks", "detail", taskId] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["subtasks", "by-task", taskId] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["reviews"] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["notifications"] });
  });

  it("also refreshes a contributor's subtask history after a mutation", async () => {
    const invalidateQueries = jest.fn(async () => undefined);
    await invalidateSubtaskWorkflow({ invalidateQueries }, subtaskId, taskId);

    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["subtasks", "detail", subtaskId] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["subtasks", "progress", subtaskId, 0] });
    expect(invalidateQueries).toHaveBeenCalledWith({ queryKey: ["subtasks", "submissions", subtaskId, 0] });
  });
});
