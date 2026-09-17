import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, waitFor } from "@testing-library/react-native";

import type { Task } from "@/contracts/tasks";
import { TaskSubmitScreen } from "@/features/tasks/screens/task-submit-screen";

const mockRouter = { replace: jest.fn() };
const mockGetTask = jest.fn();
const mockListSubtasksByTask = jest.fn();
const mockGetTaskEvidenceRules = jest.fn();
const mockSubmitTaskEvidence = jest.fn();
const mockInvalidateTaskWorkflow = jest.fn();
const userId = "11111111-1111-4111-8111-111111111111";
const taskId = "22222222-2222-4222-8222-222222222222";

jest.mock("expo-router", () => ({
  useRouter: () => mockRouter,
  Color: {
    ios: {
      systemBackground: "#FFFFFF",
      label: "#000000",
      secondaryLabel: "#666666",
      separator: "#CCCCCC",
      systemBlue: "#2563EB"
    },
    android: {
      dynamic: {
        surface: "#FFFFFF",
        onSurface: "#000000",
        onSurfaceVariant: "#666666",
        outlineVariant: "#CCCCCC",
        primary: "#2563EB"
      }
    }
  }
}));
jest.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ state: { kind: "authorized", profile: { id: userId, role: "employee" } } })
}));
jest.mock("@/lib/phase-1/capabilities", () => ({ isPhase1CapabilityEnabled: () => true }));
jest.mock("@/features/tasks/api/tasks-api", () => ({
  TASK_PAGE_SIZE: 30,
  getTask: (...args: unknown[]) => mockGetTask(...args),
  listMyTasks: jest.fn(),
  listLeadingTasks: jest.fn(),
  listTaskAttachments: jest.fn(),
  listTaskSubmissions: jest.fn()
}));
jest.mock("@/features/subtasks/api/subtasks-api", () => ({
  SUBTASK_PAGE_SIZE: 30,
  getSubtask: jest.fn(),
  listMySubtasks: jest.fn(),
  listSubtaskProgress: jest.fn(),
  listSubtaskSubmissionAttachments: jest.fn(),
  listSubtaskSubmissions: jest.fn(),
  listSubtasksByTask: (...args: unknown[]) => mockListSubtasksByTask(...args)
}));
jest.mock("@/features/subtasks/evidence-storage", () => ({
  getTaskEvidenceRules: (...args: unknown[]) => mockGetTaskEvidenceRules(...args)
}));
jest.mock("@/features/subtasks/components/evidence-picker-preview", () => ({
  EvidencePickerPreview: () => null
}));
jest.mock("@/features/tasks/task-submission", () => ({
  submitTaskEvidence: (...args: unknown[]) => mockSubmitTaskEvidence(...args)
}));
jest.mock("@/features/workflow/cache-invalidation", () => ({
  invalidateTaskWorkflow: (...args: unknown[]) => mockInvalidateTaskWorkflow(...args)
}));

const task = {
  id: taskId,
  title: "Prepare service report",
  status: "in_progress",
  description: null,
  priority: null,
  dueDate: null,
  deadline: null,
  percentComplete: 50,
  assignedTo: userId,
  recommendationLeadId: null,
  assigneeName: "Task Lead",
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
  projectTitle: null,
  tags: [],
  subtaskCount: 0,
  subtaskCompletedCount: 0,
  createdAt: null,
  updatedAt: null
} satisfies Task;

const rules = {
  bucketId: "task-attachments" as const,
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 10,
  recommendedSignedUrlSeconds: 300,
  orphanMinimumAgeHours: 24,
  acceptedMimeTypes: ["application/pdf"]
};

describe("TaskSubmitScreen", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetTask.mockResolvedValue(task);
    mockListSubtasksByTask.mockResolvedValue([]);
    mockGetTaskEvidenceRules.mockResolvedValue(rules);
    mockSubmitTaskEvidence.mockResolvedValue(undefined);
    mockInvalidateTaskWorkflow.mockResolvedValue(undefined);
  });

  it("requires a completion note before an eligible task lead can submit", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 }, mutations: { retry: false } } });
    const view = await render(
      <QueryClientProvider client={client}>
        <TaskSubmitScreen taskId={taskId} />
      </QueryClientProvider>
    );

    await waitFor(() => expect(view.getByLabelText("Submit task for review")).toBeTruthy());
    expect(view.getByLabelText("Submit task for review").props.accessibilityState.disabled).toBe(true);
    expect(view.getByText("Add a completion note before submitting this task.")).toBeTruthy();

    await fireEvent.changeText(view.getByLabelText("Completion note"), "The report is complete.");
    await waitFor(() => expect(
      view.getByLabelText("Submit task for review").props.accessibilityState.disabled
    ).toBe(false));
    view.unmount();
    client.clear();
  });
});
