import { GatewayError } from "@/lib/gateway/errors";
import { shouldRetryQuery } from "@/lib/query/client";

describe("query retry policy", () => {
  it("retries only transient failures with a strict bound", () => {
    expect(shouldRetryQuery(0, new GatewayError("network", "offline"))).toBe(true);
    expect(shouldRetryQuery(1, new GatewayError("timeout", "slow"))).toBe(true);
    expect(shouldRetryQuery(2, new GatewayError("network", "offline"))).toBe(false);
  });

  it("does not retry authentication, authorization, or validation failures", () => {
    expect(shouldRetryQuery(0, new GatewayError("authentication", "expired"))).toBe(false);
    expect(shouldRetryQuery(0, new GatewayError("authorization", "denied"))).toBe(false);
    expect(shouldRetryQuery(0, { status: 400 })).toBe(false);
  });
});

