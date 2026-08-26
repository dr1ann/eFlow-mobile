import { z } from "zod";

import { GatewayClient } from "@/lib/gateway/client";

function response(status: number, payload: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload
  } as Response;
}

describe("GatewayClient", () => {
  it("refreshes a rotated endpoint once for a safe read", async () => {
    const resolved: boolean[] = [];
    const requested: string[] = [];
    const client = new GatewayClient({
      getAccessToken: async () => "token-not-logged",
      resolveEndpoint: async ({ forceRefresh } = {}) => {
        resolved.push(Boolean(forceRefresh));
        return forceRefresh ? "https://new.example/controlpanelEflow/api" : "https://old.example/controlpanelEflow/api";
      },
      clearEndpointCache: jest.fn(),
      fetchImpl: async (url) => {
        requested.push(String(url));
        return requested.length === 1 ? response(503, {}) : response(200, { ok: true });
      }
    });

    await expect(client.requestJson({ path: "health", schema: z.object({ ok: z.boolean() }) })).resolves.toEqual({ ok: true });
    expect(resolved).toEqual([false, true]);
    expect(requested).toEqual([
      "https://old.example/controlpanelEflow/api/health",
      "https://new.example/controlpanelEflow/api/health"
    ]);
  });

  it("does not repeat a mutation without an idempotency contract", async () => {
    const fetchImpl = jest.fn(async () => response(503, {}));
    const client = new GatewayClient({
      getAccessToken: async () => "token-not-logged",
      resolveEndpoint: async () => "https://gateway.example/controlpanelEflow/api",
      fetchImpl
    });

    await expect(client.requestJson({
      path: "sensitive-action",
      method: "POST",
      body: { action: "approve" },
      schema: z.object({ ok: z.boolean() })
    })).rejects.toMatchObject({ kind: "http", status: 503 });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});

