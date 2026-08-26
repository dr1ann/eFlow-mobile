import { Text } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

/** A deliberately permission-gated Phase 0 route used for deep-link verification. */
export function AccessCheckScreen() {
  return (
    <AppScreen testID="access-check-screen">
      <Text style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        Authorized access check
      </Text>
      <StatusNotice tone="success">
        This route is visible only when the verified effective permission allows it.
      </StatusNotice>
    </AppScreen>
  );
}

