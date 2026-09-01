import type { Href } from "expo-router";
import { useRouter } from "expo-router";
import { Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { useAuth } from "@/features/auth/auth-context";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

interface MoreDestination {
  description: string;
  href: Href;
  label: string;
}

export function MoreScreen() {
  const { can } = useAuth();
  const router = useRouter();
  const destinations: MoreDestination[] = [
    ...(can("navigation.tasks")
      ? [{ label: "Reviews", description: "Review work routed to your account.", href: "/reviews" as Href }]
      : []),
    ...(can("navigation.announcements")
      ? [{ label: "Notices", description: "Read announcements sent to your audience.", href: "/announcements" as Href }]
      : []),
    { label: "Settings", description: "View your account and sign out safely.", href: "/settings" as Href }
  ];

  return (
    <AppScreen testID="more-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          More
        </Text>
        <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Access the mobile areas available to your verified account.
        </Text>
      </View>
      <View style={{ gap: tokens.space.md }}>
        {destinations.map((destination) => (
          <View key={destination.label} style={{ gap: tokens.space.xs }}>
            <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
              {destination.description}
            </Text>
            <Button
              label={destination.label}
              variant="secondary"
              onPress={() => router.push(destination.href)}
            />
          </View>
        ))}
      </View>
    </AppScreen>
  );
}
