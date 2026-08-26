import { z } from "zod";

const runtimeConfigSchema = z.object({
  supabaseUrl: z.string().url("Enter a valid EXPO_PUBLIC_SUPABASE_URL."),
  supabasePublishableKey: z.string().min(1, "Set EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY."),
  allowInsecureLocalGateway: z.boolean()
});

export type RuntimeConfig = z.infer<typeof runtimeConfigSchema>;

export type RuntimeConfigResult =
  | { ok: true; value: RuntimeConfig }
  | { ok: false; message: string };

function parseBoolean(value: string | undefined): boolean {
  return value?.trim().toLowerCase() === "true";
}

export function readRuntimeConfig(): RuntimeConfigResult {
  const result = runtimeConfigSchema.safeParse({
    supabaseUrl: process.env.EXPO_PUBLIC_SUPABASE_URL,
    supabasePublishableKey: process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    allowInsecureLocalGateway:
      process.env.NODE_ENV !== "production" &&
      parseBoolean(process.env.EXPO_PUBLIC_ALLOW_INSECURE_LOCAL_GATEWAY)
  });

  if (result.success) return { ok: true, value: result.data };

  return {
    ok: false,
    message: result.error.issues[0]?.message ?? "Mobile configuration is invalid."
  };
}

export function requireRuntimeConfig(): RuntimeConfig {
  const result = readRuntimeConfig();
  if (!result.ok) throw new RuntimeConfigurationError(result.message);
  return result.value;
}

export class RuntimeConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RuntimeConfigurationError";
  }
}
