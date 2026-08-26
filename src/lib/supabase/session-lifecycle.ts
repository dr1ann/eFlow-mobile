import { AppState } from "react-native";

import { getSupabaseClient } from "@/lib/supabase/client";

/** Starts token refresh only while the native app is active. */
export function bindSupabaseSessionLifecycle(): () => void {
  const supabase = getSupabaseClient();

  const updateRefreshState = (state: string): void => {
    if (state === "active") supabase.auth.startAutoRefresh();
    else supabase.auth.stopAutoRefresh();
  };

  updateRefreshState(AppState.currentState);
  const subscription = AppState.addEventListener("change", updateRefreshState);

  return () => {
    subscription.remove();
    supabase.auth.stopAutoRefresh();
  };
}

