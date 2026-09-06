import * as SecureStore from "expo-secure-store";
import { z } from "zod";

import type { AiJobOperation } from "@/contracts/ai-jobs";

export interface JobPersistenceDriver {
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(key: string, value: string): Promise<void>;
  deleteItemAsync(key: string): Promise<void>;
}

export interface ResumableAiJobRecord {
  version: 1;
  userId: string;
  environment: string;
  operation: AiJobOperation;
  jobId: string;
  referenceId: string;
  createdAtMs: number;
  expiresAtMs: number;
}

const STORAGE_KEY = "eflow.phase3.jobs.v1";
const MAX_RECORDS = 20;

const recordSchema = z.object({
  version: z.literal(1),
  userId: z.string().uuid(),
  environment: z.string().trim().min(1).max(64),
  operation: z.enum(["management_brief", "proposal_decomposition"]),
  jobId: z.string().trim().min(1).max(160).regex(/^[A-Za-z0-9._:-]+$/),
  referenceId: z.string().trim().min(1).max(160).regex(/^[A-Za-z0-9._:-]+$/),
  createdAtMs: z.number().int().nonnegative(),
  expiresAtMs: z.number().int().positive()
});

const recordListSchema = z.array(recordSchema).max(MAX_RECORDS);

function deduplicateAndBound(records: readonly ResumableAiJobRecord[]): ResumableAiJobRecord[] {
  const current = new Map<string, ResumableAiJobRecord>();
  for (const record of records) {
    const key = `${record.userId}:${record.environment}:${record.operation}:${record.jobId}`;
    current.set(key, record);
  }

  return [...current.values()]
    .sort((left, right) => right.createdAtMs - left.createdAtMs)
    .slice(0, MAX_RECORDS);
}

async function readRecords(
  driver: JobPersistenceDriver,
  nowMs: number
): Promise<ResumableAiJobRecord[]> {
  const raw = await driver.getItemAsync(STORAGE_KEY);
  if (!raw) return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    await driver.deleteItemAsync(STORAGE_KEY);
    return [];
  }

  const result = recordListSchema.safeParse(parsed);
  if (!result.success) {
    await driver.deleteItemAsync(STORAGE_KEY);
    return [];
  }

  const active = deduplicateAndBound(result.data.filter((record) => record.expiresAtMs > nowMs));
  if (active.length !== result.data.length) {
    if (active.length === 0) await driver.deleteItemAsync(STORAGE_KEY);
    else await driver.setItemAsync(STORAGE_KEY, JSON.stringify(active));
  }
  return active;
}

export async function loadResumableAiJobs(
  userId: string,
  environment: string,
  nowMs = Date.now(),
  driver: JobPersistenceDriver = SecureStore
): Promise<readonly ResumableAiJobRecord[]> {
  const records = await readRecords(driver, nowMs);
  return records.filter((record) => record.userId === userId && record.environment === environment);
}

export async function saveResumableAiJob(
  record: ResumableAiJobRecord,
  driver: JobPersistenceDriver = SecureStore
): Promise<void> {
  const parsed = recordSchema.safeParse(record);
  if (!parsed.success || parsed.data.expiresAtMs <= parsed.data.createdAtMs) {
    throw new Error("The resumable job record is invalid.");
  }

  const records = await readRecords(driver, Date.now());
  const next = deduplicateAndBound([...records, parsed.data]);
  await driver.setItemAsync(STORAGE_KEY, JSON.stringify(next));
}

export async function removeResumableAiJob(
  userId: string,
  environment: string,
  operation: AiJobOperation,
  jobId: string,
  driver: JobPersistenceDriver = SecureStore
): Promise<void> {
  const records = await readRecords(driver, Date.now());
  const next = records.filter(
    (record) =>
      !(
        record.userId === userId &&
        record.environment === environment &&
        record.operation === operation &&
        record.jobId === jobId
      )
  );
  if (next.length === 0) await driver.deleteItemAsync(STORAGE_KEY);
  else await driver.setItemAsync(STORAGE_KEY, JSON.stringify(next));
}

/** Clears protected resumable identifiers when an account session ends. */
export async function clearResumableAiJobs(
  driver: JobPersistenceDriver = SecureStore
): Promise<void> {
  await driver.deleteItemAsync(STORAGE_KEY);
}
