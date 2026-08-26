import { QueryClient } from "@tanstack/react-query";

import { GatewayError } from "@/lib/gateway/errors";

export function shouldRetryQuery(failureCount: number, error: unknown): boolean {
  if (failureCount >= 2) return false;

  if (error instanceof GatewayError) {
    return error.kind === "network" || error.kind === "timeout" ||
      (error.kind === "http" && (error.status ?? 0) >= 500);
  }

  const status =
    typeof error === "object" && error !== null && "status" in error
      ? Number((error as { status?: unknown }).status)
      : undefined;
  if (status !== undefined && Number.isFinite(status)) return status >= 500;

  return true;
}

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        gcTime: 10 * 60_000,
        retry: shouldRetryQuery,
        refetchOnWindowFocus: true
      },
      mutations: {
        retry: false
      }
    }
  });
}

