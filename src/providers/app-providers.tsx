import type { PropsWithChildren } from "react";
import React from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { AuthProvider } from "@/features/auth/auth-context";
import { createQueryClient } from "@/lib/query/client";
import { bindQueryLifecycle } from "@/lib/query/lifecycle";

export function AppProviders({ children }: PropsWithChildren) {
  const [queryClient] = React.useState(createQueryClient);

  React.useEffect(() => bindQueryLifecycle(), []);

  return (
    <SafeAreaProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>{children}</AuthProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}

