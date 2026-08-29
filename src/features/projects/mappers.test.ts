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
      archived_at: null,
      updated_at: "2026-08-26T00:00:00+00:00"
    })).toMatchObject({ id: projectId, title: "Records modernization" });
  });

  it("fails closed for a malformed project record", () => {
    expect(() => mapProjectOverviewRow({ id: "bad", title: "Project" })).toThrow(ContractMappingError);
  });
});
