export const queryKeys = {
  profile: (userId: string) => ["profile", userId] as const,
  gatewayHealth: () => ["gateway", "health"] as const
};

