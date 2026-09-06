import {
  INITIAL_JOB_POLL_DELAY_MS,
  MAX_JOB_OBSERVATION_MS,
  canObserveAiJob,
  isTerminalAiJobState,
  nextAiJobPollDelay,
  parseAiJobStatus
} from "@/contracts/ai-jobs";

describe("AI job contracts", () => {
  it("accepts only bounded opaque IDs and known server states", () => {
    expect(parseAiJobStatus({ id: "job_42:brief", state: "running", retry_after_ms: 5_000 }))
      .toEqual({ id: "job_42:brief", state: "running", retryAfterMs: 5_000 });
    expect(parseAiJobStatus({ id: "job with private text", state: "succeeded" })).toBeNull();
    expect(parseAiJobStatus({ id: "job_42", state: "invented" })).toBeNull();
  });

  it("uses bounded jittered backoff, respects retry-after, and stops at five minutes", () => {
    expect(nextAiJobPollDelay(0, null, () => 0.5)).toBe(INITIAL_JOB_POLL_DELAY_MS);
    expect(nextAiJobPollDelay(20, null, () => 1)).toBeLessThanOrEqual(36_000);
    expect(nextAiJobPollDelay(0, 17_000, () => 0)).toBe(17_000);
    expect(canObserveAiJob(1_000, 1_000 + MAX_JOB_OBSERVATION_MS - 1)).toBe(true);
    expect(canObserveAiJob(1_000, 1_000 + MAX_JOB_OBSERVATION_MS)).toBe(false);
  });

  it("distinguishes terminal states from work that can still be observed", () => {
    expect(isTerminalAiJobState("queued")).toBe(false);
    expect(isTerminalAiJobState("running")).toBe(false);
    expect(isTerminalAiJobState("cancelled")).toBe(true);
    expect(isTerminalAiJobState("succeeded")).toBe(true);
  });
});
