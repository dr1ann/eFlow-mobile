import {
  clearResumableAiJobs,
  loadResumableAiJobs,
  removeResumableAiJob,
  saveResumableAiJob,
  type JobPersistenceDriver,
  type ResumableAiJobRecord
} from "@/lib/gateway/jobs/persistence";

const userId = "11111111-1111-4111-8111-111111111111";
const otherUserId = "22222222-2222-4222-8222-222222222222";
const FUTURE_NOW = 2_000_000_000_000;

function createMemoryDriver(): JobPersistenceDriver & { values: Map<string, string> } {
  const values = new Map<string, string>();
  return {
    values,
    getItemAsync: async (key) => values.get(key) ?? null,
    setItemAsync: async (key, value) => {
      values.set(key, value);
    },
    deleteItemAsync: async (key) => {
      values.delete(key);
    }
  };
}

function record(overrides: Partial<ResumableAiJobRecord> = {}): ResumableAiJobRecord {
  return {
    version: 1,
    userId,
    environment: "development",
    operation: "management_brief",
    jobId: "brief-job-1",
    referenceId: "report-1",
    createdAtMs: FUTURE_NOW,
    expiresAtMs: FUTURE_NOW + 10_000,
    ...overrides
  };
}

describe("resumable AI job persistence", () => {
  it("keeps only the current user and environment's unexpired safe identifiers", async () => {
    const driver = createMemoryDriver();
    await saveResumableAiJob(record(), driver);
    await saveResumableAiJob(record({ userId: otherUserId, jobId: "brief-job-2" }), driver);
    await saveResumableAiJob(record({ jobId: "expired-job", expiresAtMs: FUTURE_NOW + 1 }), driver);

    await expect(loadResumableAiJobs(userId, "development", FUTURE_NOW + 2_000, driver)).resolves.toEqual([
      record()
    ]);
    await expect(loadResumableAiJobs(userId, "production", FUTURE_NOW + 2_000, driver)).resolves.toEqual([]);
  });

  it("replaces a matching job, rejects malformed records, and removes data on corruption", async () => {
    const driver = createMemoryDriver();
    await saveResumableAiJob(record(), driver);
    await saveResumableAiJob(record({ referenceId: "report-2", createdAtMs: FUTURE_NOW + 1 }), driver);
    await expect(loadResumableAiJobs(userId, "development", FUTURE_NOW + 2_000, driver)).resolves.toEqual([
      record({ referenceId: "report-2", createdAtMs: FUTURE_NOW + 1 })
    ]);

    await expect(saveResumableAiJob(record({ referenceId: "private report text" }), driver)).rejects.toThrow(/invalid/i);

    driver.values.set("eflow.phase3.jobs.v1", "not JSON");
    await expect(loadResumableAiJobs(userId, "development", FUTURE_NOW + 2_000, driver)).resolves.toEqual([]);
    expect(driver.values.size).toBe(0);
  });

  it("removes a terminal job and clears all protected identifiers at sign-out", async () => {
    const driver = createMemoryDriver();
    await saveResumableAiJob(record(), driver);
    await removeResumableAiJob(userId, "development", "management_brief", "brief-job-1", driver);
    await expect(loadResumableAiJobs(userId, "development", FUTURE_NOW + 2_000, driver)).resolves.toEqual([]);

    await saveResumableAiJob(record(), driver);
    await clearResumableAiJobs(driver);
    await expect(loadResumableAiJobs(userId, "development", FUTURE_NOW + 2_000, driver)).resolves.toEqual([]);
  });
});
