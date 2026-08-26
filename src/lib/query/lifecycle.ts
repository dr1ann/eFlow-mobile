import { focusManager, onlineManager } from "@tanstack/react-query";
import NetInfo from "@react-native-community/netinfo";
import { AppState } from "react-native";

/** Connects React Query's browser-oriented lifecycle to native app state. */
export function bindQueryLifecycle(): () => void {
  const appStateSubscription = AppState.addEventListener("change", (state) => {
    focusManager.setFocused(state === "active");
  });

  const networkUnsubscribe = NetInfo.addEventListener((state) => {
    onlineManager.setOnline(
      state.isConnected === true && state.isInternetReachable !== false
    );
  });

  return () => {
    appStateSubscription.remove();
    networkUnsubscribe();
  };
}

