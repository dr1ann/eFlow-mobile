import type { PropsWithChildren } from "react";
import { ScrollView, type ScrollViewProps } from "react-native";

import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

type AppScreenProps = PropsWithChildren<
  Pick<ScrollViewProps, "refreshControl" | "testID">
>;

export function AppScreen({ children, refreshControl, testID }: AppScreenProps) {
  return (
    <ScrollView
      testID={testID}
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      refreshControl={refreshControl}
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{
        flexGrow: 1,
        padding: tokens.space.xl,
        gap: tokens.space.lg
      }}
    >
      {children}
    </ScrollView>
  );
}

