export const PHASE_3_CAPABILITIES = [
  "notificationSummary",
  "pushRegistration",
  "pushPreferences",
  "chatRead",
  "chatSend",
  "chatReadState",
  "chatEdit",
  "chatReactions",
  "chatAttachments",
  "briefJobs",
  "proposalDrafts",
  "proposalSourceUpload",
  "proposalProcessing",
  "proposalReview",
  "proposalCommit"
] as const;

export type Phase3Capability = (typeof PHASE_3_CAPABILITIES)[number];

const knownCapabilities = new Set<string>(PHASE_3_CAPABILITIES);

/**
 * Parses the explicit Phase 3 rollout allow-list. It controls only mobile
 * presentation and request paths; RLS, RPCs, Storage, and gateway
 * authorization remain the security boundary for every protected operation.
 */
export function parsePhase3Capabilities(value: string | undefined): ReadonlySet<Phase3Capability> {
  const enabled = new Set<Phase3Capability>();

  for (const candidate of value?.split(",") ?? []) {
    const capability = candidate.trim();
    if (knownCapabilities.has(capability)) enabled.add(capability as Phase3Capability);
  }

  return enabled;
}

export function configuredPhase3Capabilities(): ReadonlySet<Phase3Capability> {
  return parsePhase3Capabilities(process.env.EXPO_PUBLIC_PHASE_3_LIVE_CAPABILITIES);
}

export function isPhase3CapabilityEnabled(capability: Phase3Capability): boolean {
  return configuredPhase3Capabilities().has(capability);
}

/** Fixtures are explicit development-only adapters and cannot be shipped. */
export function isPhase3FixtureMode(
  value = process.env.EXPO_PUBLIC_PHASE_3_USE_FIXTURES,
  isDevelopment = process.env.NODE_ENV !== "production"
): boolean {
  return isDevelopment && value?.trim().toLowerCase() === "true";
}
