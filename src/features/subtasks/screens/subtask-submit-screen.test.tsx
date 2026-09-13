import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, waitFor } from "@testing-library/react-native";

import type { Subtask } from "@/contracts/subtasks";
import { SubtaskSubmitScreen } from "@/features/subtasks/screens/subtask-submit-screen";

const mockRouter = { replace: jest.fn() };
const mockGetSubtask = jest.fn();
const mockGetTaskEvidenceRules = jest.fn();
const mockSubmitSubtaskEvidence = jest.fn();
const mockInvalidateSubtaskWorkflow = jest.fn();
const userId = "11111111-1111-4111-8111-111111111111";
const subtaskId = "22222222-2222-4222-8222-222222222222";

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
jest.mock("@/features/subtasks/api/subtasks-api", () => ({
  SUBTASK_PAGE_SIZE: 30,
  getSubtask: (...args: unknown[]) => mockGetSubtask(...args),
  listMySubtasks: jest.fn(),
  listSubtaskProgress: jest.fn(),
  listSubtaskSubmissionAttachments: jest.fn(),
  listSubtaskSubmissions: jest.fn(),
  listSubtasksByTask: jest.fn()
}));
jest.mock("@/features/subtasks/evidence-storage", () => ({
  getTaskEvidenceRules: (...args: unknown[]) => mockGetTaskEvidenceRules(...args)
}));
jest.mock("@/features/subtasks/components/evidence-picker-preview", () => ({
  EvidencePickerPreview: () => null
}));
jest.mock("@/features/subtasks/subtask-submission", () => ({
  submitSubtaskEvidence: (...args: unknown[]) => mockSubmitSubtaskEvidence(...args)
}));
jest.mock("@/features/workflow/cache-invalidation", () => ({
  invalidateSubtaskWorkflow: (...args: unknown[]) => mockInvalidateSubtaskWorkflow(...args)
}));

const subtask = {
  id: subtaskId,
  taskId: "33333333-3333-4333-8333-333333333333",
  title: "Collect source figures",
  status: "changes_requested",
  percentComplete: 60,
  assignedTo: userId,
  assignedToIds: [],
  reviewerId: "44444444-4444-4444-8444-444444444444",
  dueDate: null,
  position: 1,
  isCompleted: false,
  latestSubmissionId: "55555555-5555-4555-8555-555555555555",
  source: null,
  createdAt: null,
  updatedAt: null
} satisfies Subtask;

const rules = {
  bucketId: "task-attachments" as const,
  maximumBytesPerFile: 100,
  maximumFilesPerSubmission: 10,
  recommendedSignedUrlSeconds: 300,
  orphanMinimumAgeHours: 24,
  acceptedMimeTypes: ["application/pdf"]
};

describe("SubtaskSubmitScreen", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSubtask.mockResolvedValue(subtask);
    mockGetTaskEvidenceRules.mockResolvedValue(rules);
    mockSubmitSubtaskEvidence.mockResolvedValue(undefined);
    mockInvalidateSubtaskWorkflow.mockResolvedValue(undefined);
  });

  it("labels requested changes as a resubmission and requires a completion note", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 }, mutations: { retry: false } } });
    const view = await render(
      <QueryClientProvider client={client}>
        <SubtaskSubmitScreen subtaskId={subtaskId} />
      </QueryClientProvider>
    );

    await waitFor(() => expect(view.getByText("Resubmit subtask")).toBeTruthy());
    expect(view.getByLabelText("Resubmit for review").props.accessibilityState.disabled).toBe(true);
    expect(view.getByText("Add a completion note before submitting this subtask.")).toBeTruthy();

    await fireEvent.changeText(view.getByLabelText("Completion note"), "Corrected the ledger attachment.");
    await waitFor(() => expect(
      view.getByLabelText("Resubmit for review").props.accessibilityState.disabled
    ).toBe(false));
    view.unmount();
    client.clear();
  });
});
