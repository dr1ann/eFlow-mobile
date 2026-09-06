import { z } from "zod";

export const AI_JOB_STATES = [
  "queued",
  "running",
  "succeeded",
  "failed",
  "expired",
  "cancelled"
] as const;

export type AiJobState = (typeof AI_JOB_STATES)[number];
export type AiJobOperation = "management_brief" | "proposal_decomposition";

export const INITIAL_JOB_POLL_DELAY_MS = 2_000;
export const MAX_JOB_POLL_DELAY_MS = 30_000;
export const MAX_JOB_OBSERVATION_MS = 5 * 60_000;

const jobIdSchema = z.string().trim().min(1).max(160).regex(/^[A-Za-z0-9._:-]+$/);
const jobStateSchema = z.enum(AI_JOB_STATES);

export interface AiJobStatus {
  id: string;
  state: AiJobState;
  retryAfterMs: number | null;
}

export function parseAiJobStatus(value: unknown): AiJobStatus | null {
  const parsed = z
    .object({
      id: jobIdSchema,
      state: jobStateSchema,
      retry_after_ms: z.number().int().positive().max(MAX_JOB_OBSERVATION_MS).nullable().optional()
    })
    .safeParse(value);
  if (!parsed.success) return null;

  return {
    id: parsed.data.id,
    state: parsed.data.state,
    retryAfterMs: parsed.data.retry_after_ms ?? null
  };
}

export function isTerminalAiJobState(state: AiJobState): boolean {
  return state === "succeeded" || state === "failed" || state === "expired" || state === "cancelled";
}

/**
 * Uses bounded foreground backoff with deterministic injectable jitter for
 * tests. A valid server Retry-After is respected without being jittered.
 */
export function nextAiJobPollDelay(
  failedPolls: number,
  retryAfterMs: number | null,
  random: () => number = Math.random
): number {
  if (retryAfterMs !== null && retryAfterMs > 0) return retryAfterMs;

  const exponent = Math.max(0, Math.min(failedPolls, 20));
  const base = Math.min(MAX_JOB_POLL_DELAY_MS, INITIAL_JOB_POLL_DELAY_MS * 2 ** exponent);
  const jitter = 0.8 + Math.max(0, Math.min(1, random())) * 0.4;
  return Math.round(base * jitter);
}

export function canObserveAiJob(
  observationStartedAtMs: number,
  nowMs: number
): boolean {
  return nowMs - observationStartedAtMs < MAX_JOB_OBSERVATION_MS;
}
