import { ContractMappingError } from "@/contracts/contract-errors";
import {
  mapSubtaskProgressRow,
  mapSubtaskRow,
  mapSubtaskSubmissionRow
} from "@/features/subtasks/mappers";

const ids = {
  task: "11111111-1111-4111-8111-111111111111",
  subtask: "22222222-2222-4222-8222-222222222222",
  employee: "33333333-3333-4333-8333-333333333333",
  reviewer: "44444444-4444-4444-8444-444444444444",
  submission: "55555555-5555-4555-8555-555555555555",
  progress: "66666666-6666-4666-8666-666666666666"
};

function subtaskRow(overrides: Record<string, unknown> = {}): unknown {
  return {
    id: ids.subtask,
    task_id: ids.task,
    title: "Collect evidence",
    status: "changes_requested",
    percent_complete: 99,
    assigned_to: ids.employee,
    assigned_to_ids: [ids.employee],
    reviewer_id: ids.reviewer,
    due_date: "2026-08-30",
    position: 1,
    is_standalone: true,
    is_completed: false,
    latest_submission_id: ids.submission,
    source: "manual",
    created_at: "2026-08-01T00:00:00+00:00",
    updated_at: "2026-08-02T00:00:00+00:00",
    ...overrides
  };
}

describe("subtask mappers", () => {
  it("maps the evidence-backed workflow fields", () => {
    expect(mapSubtaskRow(subtaskRow())).toMatchObject({
      id: ids.subtask,
      taskId: ids.task,
      status: "changes_requested",
      percentComplete: 99,
      isStandalone: true,
      isCompleted: false
    });
  });

  it("maps a subtask row when assigned_to_ids is nullish", () => {
    const mapped = mapSubtaskRow(subtaskRow({ assigned_to_ids: null }));
    expect(mapped.assignedToIds).toEqual([]);
  });

  it("fails closed for statuses outside the deployed subtask lifecycle", () => {
    expect(() => mapSubtaskRow(subtaskRow({ status: "cancelled" }))).toThrow(ContractMappingError);
  });

  it("maps progress and versioned review attempts", () => {
    const progress = mapSubtaskProgressRow({
      id: ids.progress,
      task_id: ids.task,
      subtask_id: ids.subtask,
      author_id: ids.employee,
      author_name: "Employee",
      percent_complete: 75,
      blocker_category: "Dependency",
      blocker: "Awaiting records",
      next_step: "Follow up",
      note: "Called the office",
      attachment_path: null,
      attachment_name: null,
      created_at: "2026-08-03T00:00:00+00:00"
    });
    const submission = mapSubtaskSubmissionRow({
      id: ids.submission,
      task_id: ids.task,
      subtask_id: ids.subtask,
      version: 2,
      note: "Resubmitted with corrected form",
      status: "changes_requested",
      submitter_id: ids.employee,
      submitter_name: "Employee",
      reviewer_id: ids.reviewer,
      submitted_at: "2026-08-04T00:00:00+00:00",
      decided_at: "2026-08-05T00:00:00+00:00",
      decided_by: ids.reviewer,
      decided_by_name: "Team Leader",
      decision_feedback: "Please add the signed page."
    });

    expect(progress.blocker).toBe("Awaiting records");
    expect(submission.version).toBe(2);
    expect(submission.decisionFeedback).toBe("Please add the signed page.");
  });
});
