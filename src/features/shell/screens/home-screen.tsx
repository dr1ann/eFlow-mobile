import { useQuery } from "@tanstack/react-query";
import { Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { AccessProfile } from "@/contracts/profile";
import { roleLabel } from "@/contracts/roles";
import { useAuth } from "@/features/auth/auth-context";
import { gatewayClient } from "@/lib/gateway/client";
import { gatewayErrorMessage } from "@/lib/gateway/errors";
import { queryKeys } from "@/lib/query/keys";
import { loadAccessProfile } from "@/lib/supabase/access";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function HomeScreen() {
  const { state } = useAuth();
  if (state.kind !== "authorized") return null;

  return <AuthorizedHomeScreen profile={state.profile} />;
}

function AuthorizedHomeScreen({ profile }: { profile: AccessProfile }) {
  const profileQuery = useQuery({
    queryKey: queryKeys.profile(profile.id),
    queryFn: () => loadAccessProfile(profile.id)
  });
  const healthQuery = useQuery({
    queryKey: queryKeys.gatewayHealth(),
    queryFn: ({ signal }) => gatewayClient.health(signal),
    enabled: false,
    retry: false
  });

  const profileState = profileQuery.data?.kind === "authorized" ? "Connected" : "Checking";

  return (
    <AppScreen testID="home-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Welcome, {profile.fullName || "eFlow user"}
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          {roleLabel(profile.role)} · {profile.permissions.size} effective permissions
        </Text>
      </View>

      <StatusNotice tone={profileState === "Connected" ? "success" : "warning"}>
        Supabase profile access: {profileState}
      </StatusNotice>

      {profileQuery.isError ? (
        <StatusNotice tone="danger">
          The profile check failed. Pull to refresh when you are back online.
        </StatusNotice>
      ) : null}

      <View style={{ gap: tokens.space.md }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "700" }}>
          Gateway connectivity
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
          Test the authenticated eFlow control-gateway connection. This does not call the private AI service.
        </Text>
        <Button
          label="Check gateway health"
          onPress={() => void healthQuery.refetch()}
          loading={healthQuery.isFetching}
        />
        {healthQuery.data ? (
          <StatusNotice tone="success">
            Gateway connected: {healthQuery.data.service}
          </StatusNotice>
        ) : null}
        {healthQuery.error ? (
          <StatusNotice tone="danger">{gatewayErrorMessage(healthQuery.error)}</StatusNotice>
        ) : null}
      </View>

      <StatusNotice>
        Phase 0 provides your secure mobile foundation. Tasks and reviews begin in Phase 1.
      </StatusNotice>
    </AppScreen>
  );
}
