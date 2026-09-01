import React from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  Text,
  useColorScheme,
  View
} from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { Notification } from "@/contracts/notifications";
import type { PermissionKey } from "@/contracts/permissions";
import { useAuth } from "@/features/auth/auth-context";
import { markNotificationRead } from "@/features/notifications/api/notifications-api";
import {
  canOpenNotificationDestination,
  notificationNavigationTarget
} from "@/features/notifications/navigation";
import {
  notificationsInfiniteQueryOptions,
  type NotificationFeedPage
} from "@/features/notifications/query-options";
import { formatTaskDate } from "@/features/tasks/presentation";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { queryKeys } from "@/lib/query/keys";
import { subscribeToScopedTable } from "@/lib/supabase/realtime";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function flattenNotificationFeed(
  pages: readonly NotificationFeedPage[] | undefined
): Notification[] {
  const notifications = new Map<string, Notification>();
  for (const page of pages ?? []) {
    for (const notification of page.items) notifications.set(notification.id, notification);
  }
  return [...notifications.values()];
}

interface NotificationListScreenViewProps {
  notifications: readonly Notification[];
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  canOpenNotification(notification: Notification): boolean;
  canMarkRead: boolean;
  markingNotificationId: string | null;
  onRefresh(): void;
  onLoadMore(): void;
  onOpenNotification(notification: Notification): void;
  onMarkRead(notification: Notification): void;
}

export function NotificationListScreenView({
  notifications,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  canOpenNotification,
  canMarkRead,
  markingNotificationId,
  onRefresh,
  onLoadMore,
  onOpenNotification,
  onMarkRead
}: NotificationListScreenViewProps) {
  useColorScheme();

  return (
    <FlatList
      testID="notification-list-screen"
      data={notifications}
      keyExtractor={(notification) => notification.id}
      contentInsetAdjustmentBehavior="automatic"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{
        flexGrow: 1,
        padding: tokens.space.lg,
        gap: tokens.space.md
      }}
      refreshControl={
        <RefreshControl
          refreshing={isRefreshing && !isLoading}
          onRefresh={onRefresh}
          tintColor={colors.primary}
        />
      }
      ListHeaderComponent={
        <View style={{ gap: tokens.space.md, paddingBottom: tokens.space.sm }}>
          <View style={{ gap: tokens.space.xs }}>
            <Text
              selectable
              style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}
            >
              Notifications
            </Text>
            <Text
              selectable
              style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}
            >
              Inbox events returned for your signed-in eFlow account.
            </Text>
          </View>

          <StatusNotice tone="warning">
            This inbox is read-only. Marking notifications read, live updates, and background push
            alerts remain unavailable until recipient-only backend contracts are verified.
          </StatusNotice>

          {isPaused ? (
            <StatusNotice tone="warning">
              You are offline. Showing cached notifications when available; reconnect to refresh.
            </StatusNotice>
          ) : null}

          {isError && notifications.length > 0 ? (
            <StatusNotice tone="warning">
              Refresh failed. The notifications below may be out of date.
            </StatusNotice>
          ) : null}
        </View>
      }
      renderItem={({ item }) => <View style={{ gap: tokens.space.sm }}>
        <NotificationListItem notification={item} canOpen={canOpenNotification(item)} onPress={() => onOpenNotification(item)} />
        {!item.isRead && canMarkRead ? <Button label="Mark read" variant="secondary" loading={markingNotificationId === item.id} onPress={() => onMarkRead(item)} /> : null}
      </View>}
      ListEmptyComponent={
        <View
          style={{
            flex: 1,
            minHeight: 240,
            alignItems: "center",
            justifyContent: "center",
            gap: tokens.space.md
          }}
        >
          {isLoading ? (
            <>
              <ActivityIndicator accessibilityLabel="Loading notifications" color={colors.primary} />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                Loading notifications…
              </Text>
            </>
          ) : isError ? (
            <>
              <StatusNotice tone="danger">
                We could not load notifications. Check your connection or access and try again.
              </StatusNotice>
              <Button label="Try again" onPress={onRefresh} />
            </>
          ) : (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              No notifications are available.
            </Text>
          )}
        </View>
      }
      ListFooterComponent={
        hasNextPage ? (
          <View style={{ paddingTop: tokens.space.sm }}>
            <Button label="Load more notifications" loading={isFetchingNextPage} onPress={onLoadMore} />
          </View>
        ) : null
      }
    />
  );
}

function NotificationListItem({
  notification,
  canOpen,
  onPress
}: {
  notification: Notification;
  canOpen: boolean;
  onPress(): void;
}) {
  const state = notification.isRead ? "Read" : "Unread";
  const destinationLabel = canOpen
    ? "Open linked item."
    : "No supported destination is available in your current mobile access.";

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${state} notification: ${notification.title}. ${destinationLabel}`}
      accessibilityState={{ disabled: !canOpen }}
      disabled={!canOpen}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: tokens.touchTarget,
        gap: tokens.space.sm,
        padding: tokens.space.lg,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: notification.isRead ? colors.separator : colors.primary,
        backgroundColor: colors.surface,
        opacity: !canOpen ? 0.64 : pressed ? 0.78 : 1
      })}
    >
      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: tokens.space.md }}>
        <Text
          selectable
          numberOfLines={2}
          style={{ flex: 1, color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}
        >
          {notification.title}
        </Text>
        <Text
          selectable
          style={{ color: notification.isRead ? colors.secondaryLabel : colors.primary, fontSize: tokens.type.caption, fontWeight: "700" }}
        >
          {state}
        </Text>
      </View>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
        {notification.message}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {formatTaskDate(notification.createdAt)}
      </Text>
    </Pressable>
  );
}

export function NotificationListScreen() {
  const { state, can } = useAuth();
  if (state.kind !== "authorized") return null;

  return <AuthorizedNotificationListScreen userId={state.profile.id} can={can} />;
}

function AuthorizedNotificationListScreen({
  userId,
  can
}: {
  userId: string;
  can: (permission: PermissionKey) => boolean;
}) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const query = useInfiniteQuery(notificationsInfiniteQueryOptions(userId));
  const canMarkRead = isPhase1CapabilityEnabled("notificationWrites");
  const markReadMutation = useMutation({
    mutationFn: (notificationId: string) => markNotificationRead(notificationId, userId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.notifications.feed(userId) });
      await queryClient.invalidateQueries({ queryKey: queryKeys.notifications.unread(userId) });
    }
  });

  React.useEffect(() => {
    if (!isPhase1CapabilityEnabled("phase1Realtime")) return;
    return subscribeToScopedTable(
      `notifications:${userId}`,
      "notifications",
      `user_id=eq.${userId}`,
      () => {
        void queryClient.invalidateQueries({ queryKey: queryKeys.notifications.feed(userId) });
        void queryClient.invalidateQueries({ queryKey: queryKeys.notifications.unread(userId) });
      }
    );
  }, [queryClient, userId]);

  const notifications = React.useMemo(
    () => flattenNotificationFeed(query.data?.pages),
    [query.data?.pages]
  );

  return (
    <NotificationListScreenView
      notifications={notifications}
      isLoading={query.isLoading}
      isRefreshing={query.isRefetching}
      isError={query.isError}
      isPaused={query.fetchStatus === "paused"}
      hasNextPage={query.hasNextPage ?? false}
      isFetchingNextPage={query.isFetchingNextPage}
      canOpenNotification={(notification) => canOpenNotificationDestination(notification, can)}
      canMarkRead={canMarkRead}
      markingNotificationId={markReadMutation.isPending ? markReadMutation.variables ?? null : null}
      onRefresh={() => void query.refetch()}
      onLoadMore={() => void query.fetchNextPage()}
      onOpenNotification={(notification) => {
        const target = notificationNavigationTarget(notification);
        if (!target || !can(target.requiredPermission)) return;
        router.push(target.href);
      }}
      onMarkRead={(notification) => markReadMutation.mutate(notification.id)}
    />
  );
}
