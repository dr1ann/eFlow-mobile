export const PHASE_1_CAPABILITIES = [
  "taskTransition",
  "subtaskProgress",
  "evidenceRules",
  "evidenceUpload",
  "evidenceSignedRead",
  "subtaskSubmit",
  "subtaskDecision",
  "taskSubmit",
  "taskDecision",
  "notificationWrites",
  "announcementReads",
  "taskComments",
  "phase1Realtime"
] as const;

export type Phase1Capability = (typeof PHASE_1_CAPABILITIES)[number];

const knownCapabilities = new Set<string>(PHASE_1_CAPABILITIES);

/**
 * Parses an explicitly configured, comma-separated allow-list. This only
 * controls the mobile presentation and request path: Supabase RLS/RPCs remain
 * the authorization boundary for every operation.
 */
export function parsePhase1Capabilities(value: string | undefined): ReadonlySet<Phase1Capability> {
  const enabled = new Set<Phase1Capability>();

  for (const candidate of value?.split(",") ?? []) {
    const capability = candidate.trim();
    if (knownCapabilities.has(capability)) enabled.add(capability as Phase1Capability);
  }

  return enabled;
}

export function configuredPhase1Capabilities(): ReadonlySet<Phase1Capability> {
  return parsePhase1Capabilities(process.env.EXPO_PUBLIC_PHASE_1_LIVE_CAPABILITIES);
}

export function isPhase1CapabilityEnabled(capability: Phase1Capability): boolean {
  return configuredPhase1Capabilities().has(capability);
}

/** Fixtures are opt-in and can never be enabled in a production bundle. */
export function isPhase1FixtureMode(
  value = process.env.EXPO_PUBLIC_PHASE_1_USE_FIXTURES,
  isDevelopment = process.env.NODE_ENV !== "production"
): boolean {
  return isDevelopment && value?.trim().toLowerCase() === "true";
}
