import {
  archiveCompletedProject,
  completeProject,
  createProjectWithDetails,
  getProjectCompletionReadiness,
  mapProjectCompletionReadiness
} from "@/features/projects/api/project-workflow-api";
import { ContractMappingError } from "@/contracts/contract-errors";

const mockRpc = jest.fn();

jest.mock("@/lib/phase-1/online", () => ({ requireCurrentOnlineMutation: jest.fn() }));
jest.mock("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({ rpc: mockRpc }) }));

const projectRow = {
  id: "11111111-1111-4111-8111-111111111111",
  title: "Records modernization",
  description: "Digitize records.",
  status: "planning",
  priority: "medium",
  start_date: "2026-09-01",
  target_date: "2026-10-01",
  program_title: null,
  owner_id: "22222222-2222-4222-8222-222222222222",
  org_id: "33333333-3333-4333-8333-333333333333",
  archived_at: null,
  updated_at: "2026-09-01T00:00:00+00:00"
};

const readiness = {
  projectId: projectRow.id,
  title: projectRow.title,
  status: "active",
  canComplete: false,
  blockers: [
    {
      kind: "task",
      title: "Prepare records",
      detail: "Finish and submit this task for approval.",
      taskId: "44444444-4444-4444-8444-444444444444"
    },
    {
      kind: "cash",
      title: "FR-00001 · Private cash request",
      detail: "Cash detail that must not be shown on mobile.",
      amount: 5000
    }
  ]
};

describe("project workflow RPC adapter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRpc.mockResolvedValue({ data: null, error: null });
  });

  it("creates through the atomic project RPC", async () => {
    mockRpc.mockResolvedValueOnce({ data: projectRow, error: null });

    await expect(createProjectWithDetails({ title: "Records modernization" })).resolves.toMatchObject({
      id: projectRow.id,
      status: "planning"
    });
    expect(mockRpc).toHaveBeenCalledWith("create_project_with_details", {
      p_payload: { title: "Records modernization" }
    });
  });

  it("uses the lifecycle RPCs and does not send empty notes", async () => {
    mockRpc.mockResolvedValueOnce({ data: readiness, error: null });

    await getProjectCompletionReadiness(projectRow.id);
    await completeProject(projectRow.id, "  ");
    await archiveCompletedProject(projectRow.id, " Completed record retention period ");

    expect(mockRpc).toHaveBeenNthCalledWith(1, "get_project_completion_readiness", {
      p_project_id: projectRow.id
    });
    expect(mockRpc).toHaveBeenNthCalledWith(2, "complete_project", {
      p_project_id: projectRow.id,
      p_note: undefined
    });
    expect(mockRpc).toHaveBeenNthCalledWith(3, "archive_completed_project", {
      p_project_id: projectRow.id,
      p_reason: "Completed record retention period"
    });
  });

  it("maps readiness and redacts finance-only blocker details", () => {
    expect(mapProjectCompletionReadiness(readiness)).toEqual({
      projectId: projectRow.id,
      title: projectRow.title,
      status: "active",
      canComplete: false,
      blockers: [
        {
          kind: "task",
          title: "Prepare records",
          detail: "Finish and submit this task for approval.",
          taskId: "44444444-4444-4444-8444-444444444444"
        },
        {
          kind: "financial",
          title: "Financial clearance",
          detail: "Financial clearance must be resolved on the web before this project can be completed.",
          taskId: null
        }
      ]
    });
  });

  it("fails closed for a malformed readiness payload", () => {
    expect(() => mapProjectCompletionReadiness({ projectId: projectRow.id })).toThrow(
      ContractMappingError
    );
  });
});
