import { GatewayError } from "@/lib/gateway/errors";
import { joinGatewayEndpoint, normalizeGatewayEndpoint } from "@/lib/gateway/endpoint-resolver";

describe("gateway endpoint resolution", () => {
  it("adds the audited eFlow API path to an origin-only URL", () => {
    expect(normalizeGatewayEndpoint("https://gateway.example.gov", { allowInsecureLocalGateway: false })).toBe(
      "https://gateway.example.gov/controlpanelEflow/api"
    );
  });

  it("preserves the published API path and safely joins health", () => {
    const endpoint = normalizeGatewayEndpoint(
      "https://sample-node.trycloudflare.com/controlpanelEflow/api/",
      { allowInsecureLocalGateway: false }
    );
    expect(joinGatewayEndpoint(endpoint, "health")).toBe(
      "https://sample-node.trycloudflare.com/controlpanelEflow/api/health"
    );
  });

  it("rejects insecure remote endpoints and absolute request paths", () => {
    expect(() => normalizeGatewayEndpoint("http://example.com", { allowInsecureLocalGateway: true })).toThrow(GatewayError);
    expect(() => joinGatewayEndpoint("https://gateway.example.gov/controlpanelEflow/api", "https://other.example/health")).toThrow(GatewayError);
  });
});

