import { ContractMappingError } from "@/contracts/contract-errors";
import { mapProjectOverviewRow } from "@/features/projects/mappers";

const projectId = "11111111-1111-4111-8111-111111111111";

describe("project overview mapper", () => {
  it("maps the read-only task-linked project fields", () => {
    expect(mapProjectOverviewRow({
      id: projectId,
      title: "Records modernization",
      description: "Digitize records.",
      status: "in_progress",
      priority: "high",
      start_date: "2026-08-01",
      target_date: "2026-09-01",
      program_title: "Digital services",
      owner_id: "22222222-2222-4222-8222-222222222222",
      org_id: "33333333-3333-4333-8333-333333333333",
      archived_at: null,
      updated_at: "2026-08-26T00:00:00+00:00"
    })).toMatchObject({
      id: projectId,
      title: "Records modernization",
      status: "active",
      priority: "high"
    });
  });

  it("fails closed for a malformed project record", () => {
    expect(() => mapProjectOverviewRow({ id: "bad", title: "Project" })).toThrow(ContractMappingError);
  });

  it("fails closed for an unsupported project status or priority", () => {
    const row = {
      id: projectId,
      title: "Records modernization",
      description: "Digitize records.",
      status: "unknown_status",
      priority: "high",
      start_date: null,
      target_date: null,
      program_title: null,
      owner_id: null,
      org_id: null,
      archived_at: null,
      updated_at: "2026-08-26T00:00:00+00:00"
    };

    expect(() => mapProjectOverviewRow(row)).toThrow(ContractMappingError);
    expect(() => mapProjectOverviewRow({ ...row, status: "active", priority: "urgent" })).toThrow(
      ContractMappingError
    );
  });
});
