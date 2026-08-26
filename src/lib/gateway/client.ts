import { z, type ZodType } from "zod";

import { gatewayHealthSchema, type GatewayHealth } from "@/contracts/gateway";
import { GatewayError } from "@/lib/gateway/errors";
import {
  clearGatewayEndpointCache,
  joinGatewayEndpoint,
  resolveGatewayEndpoint
} from "@/lib/gateway/endpoint-resolver";
import { getSupabaseClient } from "@/lib/supabase/client";

const RETRYABLE_GATEWAY_STATUSES = new Set([502, 503, 504, 530]);
const DEFAULT_TIMEOUT_MS = 12_000;

export interface GatewayRequestOptions<T> {
  path: string;
  schema: ZodType<T>;
  method?: "GET" | "HEAD" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  headers?: HeadersInit;
  signal?: AbortSignal;
  timeoutMs?: number;
  /** The backend must guarantee de-duplication before this is set for a mutation. */
  idempotencyKey?: string;
}

interface GatewayClientDependencies {
  fetchImpl?: typeof fetch;
  getAccessToken?: () => Promise<string>;
  resolveEndpoint?: (options?: { forceRefresh?: boolean }) => Promise<string>;
  clearEndpointCache?: () => void;
}

interface RequestSignal {
  signal: AbortSignal;
  cleanup: () => void;
  didTimeout: () => boolean;
}

function createRequestSignal(external: AbortSignal | undefined, timeoutMs: number): RequestSignal {
  const controller = new AbortController();
  let timedOut = false;

  const onExternalAbort = (): void => controller.abort();
  if (external?.aborted) controller.abort();
  else external?.addEventListener("abort", onExternalAbort, { once: true });

  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  return {
    signal: controller.signal,
    didTimeout: () => timedOut,
    cleanup: () => {
      clearTimeout(timeout);
      external?.removeEventListener("abort", onExternalAbort);
    }
  };
}

function isSafeEndpointRetry<T>(options: GatewayRequestOptions<T>): boolean {
  const method = options.method ?? "GET";
  return method === "GET" || method === "HEAD" || Boolean(options.idempotencyKey);
}

function isEndpointRetryError(error: GatewayError): boolean {
  return error.kind === "network" ||
    (error.kind === "http" && error.status !== undefined && RETRYABLE_GATEWAY_STATUSES.has(error.status));
}

function mapHttpError(status: number): GatewayError {
  if (status === 401) return new GatewayError("authentication", "Gateway authentication was rejected.", { status });
  if (status === 403) return new GatewayError("authorization", "Gateway authorization was rejected.", { status });
  return new GatewayError("http", "The gateway request was unsuccessful.", { status });
}

function isAbortError(error: unknown): boolean {
  return typeof error === "object" && error !== null &&
    "name" in error && (error as { name?: unknown }).name === "AbortError";
}

export class GatewayClient {
  private readonly fetchImpl: typeof fetch;
  private readonly getAccessToken: () => Promise<string>;
  private readonly resolveEndpoint: (options?: { forceRefresh?: boolean }) => Promise<string>;
  private readonly clearEndpointCache: () => void;

  constructor(dependencies: GatewayClientDependencies = {}) {
    this.fetchImpl = dependencies.fetchImpl ?? fetch;
    this.getAccessToken = dependencies.getAccessToken ?? (async () => {
      const { data, error } = await getSupabaseClient().auth.getSession();
      if (error || !data.session?.access_token) {
        throw new GatewayError("authentication", "A valid Supabase session is required.");
      }
      return data.session.access_token;
    });
    this.resolveEndpoint = dependencies.resolveEndpoint ?? resolveGatewayEndpoint;
    this.clearEndpointCache = dependencies.clearEndpointCache ?? clearGatewayEndpointCache;
  }

  async requestJson<T>(options: GatewayRequestOptions<T>): Promise<T> {
    const endpoint = await this.resolveEndpoint();

    try {
      return await this.requestAtEndpoint(endpoint, options);
    } catch (error) {
      if (!(error instanceof GatewayError) || !isSafeEndpointRetry(options) || !isEndpointRetryError(error)) {
        throw error;
      }

      this.clearEndpointCache();
      const refreshedEndpoint = await this.resolveEndpoint({ forceRefresh: true });
      return this.requestAtEndpoint(refreshedEndpoint, options);
    }
  }

  private async requestAtEndpoint<T>(
    endpoint: string,
    options: GatewayRequestOptions<T>
  ): Promise<T> {
    const requestSignal = createRequestSignal(
      options.signal,
      options.timeoutMs ?? DEFAULT_TIMEOUT_MS
    );

    try {
      const accessToken = await this.getAccessToken();
      const headers = new Headers(options.headers);
      headers.set("Authorization", `Bearer ${accessToken}`);
      headers.set("Accept", "application/json");
      if (options.body !== undefined) headers.set("Content-Type", "application/json");
      if (options.idempotencyKey) headers.set("Idempotency-Key", options.idempotencyKey);

      let response: Response;
      try {
        response = await this.fetchImpl(joinGatewayEndpoint(endpoint, options.path), {
          method: options.method ?? "GET",
          headers,
          body: options.body === undefined ? undefined : JSON.stringify(options.body),
          signal: requestSignal.signal
        });
      } catch (error) {
        if (requestSignal.didTimeout()) {
          throw new GatewayError("timeout", "The gateway request timed out.");
        }
        if (options.signal?.aborted || isAbortError(error)) {
          throw new GatewayError("canceled", "The gateway request was canceled.");
        }
        throw new GatewayError("network", "The gateway could not be reached.");
      }

      if (!response.ok) throw mapHttpError(response.status);
      if ((options.method ?? "GET") === "HEAD") return undefined as T;

      const payload: unknown = await response.json().catch(() => {
        throw new GatewayError("invalidResponse", "The gateway response was not JSON.");
      });
      const parsed = options.schema.safeParse(payload);
      if (!parsed.success) {
        throw new GatewayError("invalidResponse", "The gateway response did not match its contract.");
      }
      return parsed.data;
    } finally {
      requestSignal.cleanup();
    }
  }

  health(signal?: AbortSignal): Promise<GatewayHealth> {
    return this.requestJson({
      path: "health",
      schema: gatewayHealthSchema,
      signal,
      timeoutMs: 6_000
    });
  }
}

export const gatewayClient = new GatewayClient();

export const unknownGatewayResponseSchema = z.unknown();
