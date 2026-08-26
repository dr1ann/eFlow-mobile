import { Link } from "expo-router";
import { Text } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export default function NotFoundRoute() {
  return (
    <AppScreen>
      <Text style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        Page not found
      </Text>
      <Link href="/" style={{ color: colors.primary, fontSize: tokens.type.body }}>
        Return to eFlow
      </Link>
    </AppScreen>
  );
}

