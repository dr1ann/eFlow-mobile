import { GatewayError } from "@/lib/gateway/errors";
import { requireRuntimeConfig } from "@/lib/config/runtime";
import { getSupabaseClient } from "@/lib/supabase/client";

const GATEWAY_CONFIG_KEY = "ai_endpoint";

let cachedEndpoint: string | null = null;

function isPrivateDevelopmentHost(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname === "::1" ||
    hostname.startsWith("127.") ||
    hostname.startsWith("10.") ||
    hostname.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(hostname)
  );
}

export function normalizeGatewayEndpoint(
  rawValue: string,
  options: { allowInsecureLocalGateway: boolean }
): string {
  let endpoint: URL;
  try {
    endpoint = new URL(rawValue.trim());
  } catch {
    throw new GatewayError("configuration", "The published gateway endpoint is invalid.");
  }

  if (endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    throw new GatewayError("configuration", "The published gateway endpoint is unsafe.");
  }

  const isHttps = endpoint.protocol === "https:";
  const isAllowedHttp =
    endpoint.protocol === "http:" &&
    options.allowInsecureLocalGateway &&
    isPrivateDevelopmentHost(endpoint.hostname);

  if (!isHttps && !isAllowedHttp) {
    throw new GatewayError("configuration", "The published gateway endpoint must use HTTPS.");
  }

  const trimmedPath = endpoint.pathname.replace(/\/+$/, "");
  if (!trimmedPath || trimmedPath === "/") {
    endpoint.pathname = "/controlpanelEflow/api";
  } else if (trimmedPath === "/controlpanelEflow") {
    endpoint.pathname = "/controlpanelEflow/api";
  } else {
    endpoint.pathname = trimmedPath;
  }

  return endpoint.toString().replace(/\/+$/, "");
}

export function joinGatewayEndpoint(base: string, path: string): string {
  if (/^[a-z][a-z\d+.-]*:/i.test(path)) {
    throw new GatewayError("configuration", "Gateway paths must be relative.");
  }

  const normalizedBase = `${base.replace(/\/+$/, "")}/`;
  return new URL(path.replace(/^\/+/, ""), normalizedBase).toString();
}

export async function resolveGatewayEndpoint(options?: {
  forceRefresh?: boolean;
}): Promise<string> {
  if (!options?.forceRefresh && cachedEndpoint) return cachedEndpoint;

  const supabase = getSupabaseClient();
  const { data, error } = await supabase
    .from("system_config")
    .select("value")
    .eq("key", GATEWAY_CONFIG_KEY)
    .maybeSingle();

  if (error || !data?.value.trim()) {
    throw new GatewayError(
      "configuration",
      "The eFlow service endpoint has not been published."
    );
  }

  cachedEndpoint = normalizeGatewayEndpoint(data.value, requireRuntimeConfig());
  return cachedEndpoint;
}

export function clearGatewayEndpointCache(): void {
  cachedEndpoint = null;
}

