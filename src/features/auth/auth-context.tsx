import type { PropsWithChildren } from "react";
import React from "react";
import type { Session } from "@supabase/supabase-js";
import { useQueryClient } from "@tanstack/react-query";

import type { PermissionKey } from "@/contracts/permissions";
import type { AccessProfile } from "@/contracts/profile";
import { gatewayErrorMessage } from "@/lib/gateway/errors";
import { clearGatewayEndpointCache } from "@/lib/gateway/endpoint-resolver";
import { clearResumableAiJobs } from "@/lib/gateway/jobs/persistence";
import { queryKeys } from "@/lib/query/keys";
import { readRuntimeConfig } from "@/lib/config/runtime";
import { loadAccessProfile, SupabaseContractError } from "@/lib/supabase/access";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  clearRealtimeChannels,
  subscribeToCurrentProfile,
  subscribeToGatewayEndpoint,
  subscribeToRolePermissions,
  subscribeToUserPermissionOverrides
} from "@/lib/supabase/realtime";
import { bindSupabaseSessionLifecycle } from "@/lib/supabase/session-lifecycle";

export type AuthState =
  | { kind: "configuration"; message: string }
  | { kind: "booting" }
  | { kind: "signedOut" }
  | { kind: "loadingAccess"; session: Session }
  | { kind: "authorized"; session: Session; profile: AccessProfile }
  | { kind: "rejected"; session: Session; message: string };

interface AuthContextValue {
  state: AuthState;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  retryAccess(): Promise<void>;
  can(permission: PermissionKey): boolean;
}

const AuthContext = React.createContext<AuthContextValue | null>(null);

function profileRejectionMessage(kind: string): string {
  switch (kind) {
    case "missing":
      return "No eFlow profile is linked to this account. Contact your administrator.";
    case "inactive":
      return "This eFlow account is inactive. Contact your administrator.";
    case "unknownRole":
      return "This account has a role that is not supported on mobile. Contact your administrator.";
    case "malformed":
      return "This eFlow profile is incomplete. Contact your administrator.";
    default:
      return "Your eFlow access could not be verified. Try again.";
  }
}

function signInErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : "Sign-in failed.";
  if (message.includes("Invalid login credentials")) return "Invalid email or password.";
  if (message.includes("Email not confirmed")) return "Email not confirmed. Contact your administrator.";
  if (message.includes("Too many requests")) return "Too many attempts. Try again later.";
  return message;
}

export function AuthProvider({ children }: PropsWithChildren) {
  const config = readRuntimeConfig();
  const configMessage = config.ok ? undefined : config.message;
  const queryClient = useQueryClient();
  const [state, setState] = React.useState<AuthState>(() =>
    config.ok
      ? { kind: "booting" }
      : { kind: "configuration", message: configMessage ?? "Mobile configuration is invalid." }
  );
  const requestVersion = React.useRef(0);
  const mounted = React.useRef(true);

  const setSignedOut = React.useCallback(() => {
    requestVersion.current += 1;
    clearGatewayEndpointCache();
    clearRealtimeChannels();
    queryClient.clear();
    // A local sign-out cannot wait on storage I/O, but no later account may
    // inherit resumable Phase 3 job references from this session.
    void clearResumableAiJobs().catch(() => undefined);
    setState({ kind: "signedOut" });
  }, [queryClient]);

  const resolveSession = React.useCallback(
    async (session: Session | null): Promise<void> => {
      if (!session) {
        setSignedOut();
        return;
      }

      const version = ++requestVersion.current;
      setState({ kind: "loadingAccess", session });

      try {
        const resolution = await loadAccessProfile(session.user.id);
        if (!mounted.current || version !== requestVersion.current) return;

        if (resolution.kind !== "authorized") {
          queryClient.clear();
          setState({
            kind: "rejected",
            session,
            message: profileRejectionMessage(resolution.kind)
          });
          return;
        }

        queryClient.setQueryData(queryKeys.profile(session.user.id), resolution);
        setState({ kind: "authorized", session, profile: resolution.profile });
      } catch (error) {
        if (!mounted.current || version !== requestVersion.current) return;
        const message =
          error instanceof SupabaseContractError
            ? "We could not verify your eFlow access. Check your connection and try again."
            : gatewayErrorMessage(error);
        setState({ kind: "rejected", session, message });
      }
    },
    [queryClient, setSignedOut]
  );

  React.useEffect(() => {
    mounted.current = true;
    if (!config.ok) {
      return () => {
        mounted.current = false;
      };
    }

    const supabase = getSupabaseClient();
    const stopRefreshLifecycle = bindSupabaseSessionLifecycle();
    let isActive = true;

    void supabase.auth.getSession().then(({ data }) => {
      if (isActive) void resolveSession(data.session);
    }).catch(() => {
      if (isActive) setSignedOut();
    });

    const {
      data: { subscription }
    } = supabase.auth.onAuthStateChange((_event, session) => {
      // Supabase holds an auth lock during this callback. Defer all reads until
      // after it returns to avoid a startup deadlock.
      setTimeout(() => {
        if (isActive) void resolveSession(session);
      }, 0);
    });

    return () => {
      isActive = false;
      mounted.current = false;
      subscription.unsubscribe();
      stopRefreshLifecycle();
    };
  }, [config.ok, resolveSession, setSignedOut]);

  React.useEffect(() => {
    if (state.kind !== "authorized") return;

    const refreshAccess = (): void => {
      void resolveSession(state.session);
    };
    const clearGatewayCache = (): void => {
      clearGatewayEndpointCache();
    };

    const profileUnsubscribe = subscribeToCurrentProfile(state.profile.id, refreshAccess);
    const roleUnsubscribe = subscribeToRolePermissions(state.profile.role, refreshAccess);
    const overrideUnsubscribe = subscribeToUserPermissionOverrides(state.profile.id, refreshAccess);
    const endpointUnsubscribe = subscribeToGatewayEndpoint(clearGatewayCache);

    return () => {
      // Individual unsubscribers make it impossible for a stale profile to
      // receive access updates after sign-out or a user switch.
      profileUnsubscribe();
      roleUnsubscribe();
      overrideUnsubscribe();
      endpointUnsubscribe();
    };
  }, [resolveSession, state]);

  const signIn = React.useCallback(async (email: string, password: string): Promise<void> => {
    if (!config.ok) throw new Error(config.message);
    const { error } = await getSupabaseClient().auth.signInWithPassword({ email, password });
    if (error) throw new Error(signInErrorMessage(error));
  }, [config]);

  const signOut = React.useCallback(async (): Promise<void> => {
    if (!config.ok) return;
    try {
      await getSupabaseClient().auth.signOut({ scope: "local" });
    } finally {
      setSignedOut();
    }
  }, [config, setSignedOut]);

  const retryAccess = React.useCallback(async (): Promise<void> => {
    if (!config.ok) return;
    const { data } = await getSupabaseClient().auth.getSession();
    await resolveSession(data.session);
  }, [config, resolveSession]);

  const value = React.useMemo<AuthContextValue>(() => ({
    state,
    signIn,
    signOut,
    retryAccess,
    can: (permission) => state.kind === "authorized" && state.profile.permissions.has(permission)
  }), [retryAccess, signIn, signOut, state]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = React.use(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider.");
  return value;
}
