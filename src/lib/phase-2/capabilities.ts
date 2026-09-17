export const PHASE_2_CAPABILITIES = [
  "departmentOverview",
  "projectRelations",
  "projectRealtime",
  "projectCreate",
  "projectComplete",
  "projectArchive",
  "projectEdit",
  "projectMembers",
  "projectMilestones",
  "taskCreate",
  "taskAssign",
  "subtaskDeadline",
  "subtaskCreate",
  "subtaskAssign",
  "subtaskReorder",
  "subtaskExecutionRules",
  "taskDeadline",
  "teamWorkload",
  "departmentReports",
  "staffingRecommendation"
] as const;

export type Phase2Capability = (typeof PHASE_2_CAPABILITIES)[number];

const knownCapabilities = new Set<string>(PHASE_2_CAPABILITIES);

/**
 * Parses the explicit Phase 2 rollout allow-list. This controls only mobile
 * presentation and request paths; RLS, RPCs, and gateway authorization remain
 * the security boundary for every protected operation.
 */
export function parsePhase2Capabilities(value: string | undefined): ReadonlySet<Phase2Capability> {
  const enabled = new Set<Phase2Capability>();

  for (const candidate of value?.split(",") ?? []) {
    const capability = candidate.trim();
    if (knownCapabilities.has(capability)) enabled.add(capability as Phase2Capability);
  }

  return enabled;
}

export function configuredPhase2Capabilities(): ReadonlySet<Phase2Capability> {
  return parsePhase2Capabilities(process.env.EXPO_PUBLIC_PHASE_2_LIVE_CAPABILITIES);
}

export function isPhase2CapabilityEnabled(capability: Phase2Capability): boolean {
  return configuredPhase2Capabilities().has(capability);
}
