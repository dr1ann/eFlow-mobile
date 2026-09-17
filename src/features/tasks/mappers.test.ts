import { ContractMappingError } from "@/contracts/contract-errors";
import {
  mapTaskAttachmentRow,
  mapTaskRow,
  mapTaskSubmissionRow
} from "@/features/tasks/mappers";

const ids = {
  task: "11111111-1111-4111-8111-111111111111",
  user: "22222222-2222-4222-8222-222222222222",
  reviewer: "33333333-3333-4333-8333-333333333333",
  backup: "44444444-4444-4444-8444-444444444444",
  submission: "55555555-5555-4555-8555-555555555555",
  attachment: "66666666-6666-4666-8666-666666666666"
};

function taskRow(overrides: Record<string, unknown> = {}): unknown {
  return {
    id: ids.task,
    title: "Prepare report",
    status: "in_progress",
    description: "Draft the report.",
    priority: "high",
    due_date: "2026-08-30",
    deadline: null,
    percent_complete: 45,
    assigned_to: ids.user,
    recommendation_lead_id: null,
    assignee_name: "Employee",
    reviewer_id: ids.reviewer,
    backup_reviewer_id: ids.backup,
    team_member_ids: [ids.user],
    team_member_names: ["Employee"],
    team_name: "Records",
    dependency_ids: [],
    acceptance_criteria: ["Signed report", 5, "Filed copy"],
    definition_of_done: "Approved report",
    feedback: null,
    linked_project_id: null,
    project_id: null,
    project_title: null,
    tags: ["monthly"],
    subtask_count: 2,
    subtask_completed_count: 1,
    created_at: "2026-08-01T00:00:00+00:00",
    updated_at: "2026-08-02T00:00:00+00:00",
    ...overrides
  };
}

describe("task mappers", () => {
  it("maps a generated task row into the mobile contract", () => {
    expect(mapTaskRow(taskRow())).toMatchObject({
      id: ids.task,
      status: "in_progress",
      assignedTo: ids.user,
      recommendationLeadId: null,
      acceptanceCriteria: ["Signed report", "Filed copy"],
      tags: ["monthly"]
    });
  });

  it("maps proposal-imported tasks with slug project identifiers and nullish array fields", () => {
    const row = taskRow({
      project_id: "proposal-test-program-1-program-1xs-project-1-project-1ssa",
      team_member_ids: null,
      team_member_names: null,
      dependency_ids: null,
      tags: null
    });
    const mapped = mapTaskRow(row);
    expect(mapped.projectId).toBe("proposal-test-program-1-program-1xs-project-1-project-1ssa");
    expect(mapped.teamMemberIds).toEqual([]);
    expect(mapped.teamMemberNames).toEqual([]);
    expect(mapped.dependencyIds).toEqual([]);
    expect(mapped.tags).toEqual([]);
  });

  it("keeps the canonical linked project UUID separate from a legacy project hierarchy value", () => {
    const linkedProjectId = "77777777-7777-4777-8777-777777777777";
    const mapped = mapTaskRow(taskRow({
      linked_project_id: linkedProjectId,
      project_id: "proposal-test-program-1-project-hierarchy"
    }));

    expect(mapped.linkedProjectId).toBe(linkedProjectId);
    expect(mapped.projectId).toBe("proposal-test-program-1-project-hierarchy");
  });

  it("fails closed for an unsupported workflow status", () => {
    expect(() => mapTaskRow(taskRow({ status: "approved_by_ai" }))).toThrow(ContractMappingError);
  });

  it("fails closed for malformed task identity data", () => {
    expect(() => mapTaskRow(taskRow({ id: "not-a-uuid" }))).toThrow(ContractMappingError);
  });

  it("maps immutable submission and attachment metadata without generating a public URL", () => {
    const submission = mapTaskSubmissionRow({
      id: ids.submission,
      task_id: ids.task,
      version: 2,
      note: "Evidence attached",
      status: "pending",
      submitter_id: ids.user,
      submitter_name: "Employee",
      submitted_at: "2026-08-03T00:00:00+00:00",
      decided_at: null,
      decided_by: null,
      decided_by_name: null,
      decision_feedback: null
    });
    const attachment = mapTaskAttachmentRow({
      id: ids.attachment,
      task_id: ids.task,
      submission_id: ids.submission,
      file_name: "report.pdf",
      file_path: "private/path/report.pdf",
      file_size: 100,
      mime_type: "application/pdf",
      uploaded_by: ids.user,
      created_at: "2026-08-03T00:00:00+00:00"
    });

    expect(submission.version).toBe(2);
    expect(attachment.filePath).toBe("private/path/report.pdf");
    expect(attachment).not.toHaveProperty("publicUrl");
  });
});
