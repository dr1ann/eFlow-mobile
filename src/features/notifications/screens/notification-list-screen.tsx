import React from "react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  ScrollView,
  Text,
  useColorScheme,
  View
} from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { Notification } from "@/contracts/notifications";
import type { PermissionKey } from "@/contracts/permissions";
import { useAuth } from "@/features/auth/auth-context";
import {
  type NotificationFilter,
  getNotificationForRecipient,
  markAllNotificationsRead,
  markNotificationRead
} from "@/features/notifications/api/notifications-api";
import {
  canOpenNotificationDestination,
  notificationNavigationTarget
} from "@/features/notifications/navigation";
import {
  notificationsInfiniteQueryOptions,
  notificationUnreadQueryOptions,
  type NotificationFeedPage
} from "@/features/notifications/query-options";
import { formatTaskDate } from "@/features/tasks/presentation";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { isPhase3CapabilityEnabled } from "@/lib/phase-3/capabilities";
import { queryKeys } from "@/lib/query/keys";
import { SupabaseUserError } from "@/lib/supabase/errors";
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

const NOTIFICATION_FILTER_LABELS: Record<NotificationFilter, string> = {
  all: "All",
  unread: "Unread"
};

interface NotificationListScreenViewProps {
  notifications: readonly Notification[];
  filter: NotificationFilter;
  unreadCount: number | null;
  isUnreadCountLoading: boolean;
  isUnreadCountError: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  canOpenNotification(notification: Notification): boolean;
  canMarkRead: boolean;
  canMarkAllRead: boolean;
  openingNotificationId: string | null;
  markingNotificationId: string | null;
  isMarkingAllRead: boolean;
  actionError: string | null;
  markAllSucceeded: boolean;
  onFilterChange(filter: NotificationFilter): void;
  onRefresh(): void;
  onLoadMore(): void;
  onOpenNotification(notification: Notification): void;
  onMarkRead(notification: Notification): void;
  onMarkAllRead(): void;
}

export function NotificationListScreenView({
  notifications,
  filter,
  unreadCount,
  isUnreadCountLoading,
  isUnreadCountError,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  canOpenNotification,
  canMarkRead,
  canMarkAllRead,
  openingNotificationId,
  markingNotificationId,
  isMarkingAllRead,
  actionError,
  markAllSucceeded,
  onFilterChange,
  onRefresh,
  onLoadMore,
  onOpenNotification,
  onMarkRead,
  onMarkAllRead
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

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ gap: tokens.space.sm }}
          >
            {(["all", "unread"] as const).map((candidate) => {
              const selected = candidate === filter;
              return (
                <Pressable
                  key={candidate}
                  accessibilityRole="button"
                  accessibilityLabel={`Filter notifications by ${NOTIFICATION_FILTER_LABELS[candidate]}`}
                  accessibilityState={{ selected }}
                  onPress={() => onFilterChange(candidate)}
                  style={({ pressed }) => ({
                    minHeight: tokens.touchTarget,
                    justifyContent: "center",
                    paddingHorizontal: tokens.space.md,
                    borderRadius: tokens.radius.pill,
                    borderCurve: "continuous",
                    borderWidth: 1,
                    borderColor: selected ? colors.primary : colors.separator,
                    backgroundColor: selected ? colors.primary : colors.surface,
                    opacity: pressed ? 0.78 : 1
                  })}
                >
                  <Text
                    style={{
                      color: selected ? colors.onPrimary : colors.label,
                      fontSize: tokens.type.caption,
                      fontWeight: "700"
                    }}
                  >
                    {NOTIFICATION_FILTER_LABELS[candidate]}
                  </Text>
                </Pressable>
              );
            })}
          </ScrollView>

          {unreadCount !== null ? (
            <Text
              selectable
              accessibilityLabel={`${unreadCount} unread notifications`}
              style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}
            >
              {unreadCount} unread notification{unreadCount === 1 ? "" : "s"}
            </Text>
          ) : isUnreadCountLoading ? (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
              Refreshing unread total…
            </Text>
          ) : isUnreadCountError ? (
            <StatusNotice tone="warning">
              The unread total could not be refreshed. Your notification list is still available.
            </StatusNotice>
          ) : null}

          {canMarkRead ? (
            <StatusNotice tone="success">
              You can mark notifications read. Background push alerts remain unavailable until their
              separate trusted-delivery contract is verified.
            </StatusNotice>
          ) : (
            <StatusNotice tone="warning">
              Read-state changes are unavailable until the recipient-only backend checks are enabled.
            </StatusNotice>
          )}

          {canMarkAllRead && (unreadCount === null || unreadCount > 0) ? (
            <Button
              label="Mark all read"
              variant="secondary"
              loading={isMarkingAllRead}
              onPress={onMarkAllRead}
            />
          ) : null}

          {markAllSucceeded ? (
            <StatusNotice tone="success">
              Unread notifications were marked read. New events received while this was processing may
              still be unread.
            </StatusNotice>
          ) : null}

          {actionError ? <StatusNotice tone="danger">{actionError}</StatusNotice> : null}

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
      renderItem={({ item }) => (
        <View style={{ gap: tokens.space.sm }}>
          <NotificationListItem
            notification={item}
            canOpen={canOpenNotification(item)}
            opening={openingNotificationId === item.id}
            onPress={() => onOpenNotification(item)}
          />
          {!item.isRead && canMarkRead ? (
            <Button
              label="Mark read"
              variant="secondary"
              loading={markingNotificationId === item.id}
              onPress={() => onMarkRead(item)}
            />
          ) : null}
        </View>
      )}
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
  opening,
  onPress
}: {
  notification: Notification;
  canOpen: boolean;
  opening: boolean;
  onPress(): void;
}) {
  const state = notification.isRead ? "Read" : "Unread";
  const destinationLabel = opening
    ? "Opening linked item."
    : canOpen
    ? "Open linked item."
    : "No supported destination is available in your current mobile access.";

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${state} notification: ${notification.title}. ${destinationLabel}`}
      accessibilityState={{ disabled: !canOpen || opening, busy: opening }}
      disabled={!canOpen || opening}
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
  const [filter, setFilter] = React.useState<NotificationFilter>("all");
  const [openError, setOpenError] = React.useState<string | null>(null);
  const query = useInfiniteQuery(notificationsInfiniteQueryOptions(userId, filter));
  const canMarkRead = isPhase1CapabilityEnabled("notificationWrites");
  const canReadSummary = isPhase3CapabilityEnabled("notificationSummary");
  const unreadQuery = useQuery({
    ...notificationUnreadQueryOptions(userId),
    enabled: canReadSummary
  });
  const invalidateNotificationState = React.useCallback(async (): Promise<void> => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: queryKeys.notifications.feed(userId) }),
      queryClient.invalidateQueries({ queryKey: queryKeys.notifications.unread(userId) })
    ]);
  }, [queryClient, userId]);
  const markReadMutation = useMutation({
    mutationFn: (notificationId: string) => markNotificationRead(notificationId, userId),
    onSuccess: async () => {
      await invalidateNotificationState();
    }
  });
  const markAllMutation = useMutation({
    mutationFn: () => markAllNotificationsRead(userId),
    onSuccess: invalidateNotificationState
  });
  const openMutation = useMutation({
    mutationFn: async (notificationId: string) => {
      const notification = await getNotificationForRecipient(notificationId, userId);
      if (!notification) {
        throw new SupabaseUserError("not_found", "This notification is no longer available.");
      }
      return notification;
    },
    onSuccess: (notification) => {
      const target = notificationNavigationTarget(notification);
      if (!target || !can(target.requiredPermission)) {
        setOpenError("This notification is unavailable in your current mobile access.");
        return;
      }
      setOpenError(null);
      router.push(target.href);
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
      filter={filter}
      unreadCount={canReadSummary && unreadQuery.data !== undefined ? unreadQuery.data : null}
      isUnreadCountLoading={canReadSummary && unreadQuery.isLoading}
      isUnreadCountError={canReadSummary && unreadQuery.isError}
      isLoading={query.isLoading}
      isRefreshing={query.isRefetching}
      isError={query.isError}
      isPaused={query.fetchStatus === "paused"}
      hasNextPage={query.hasNextPage ?? false}
      isFetchingNextPage={query.isFetchingNextPage}
      canOpenNotification={(notification) => canOpenNotificationDestination(notification, can)}
      canMarkRead={canMarkRead}
      canMarkAllRead={canMarkRead}
      openingNotificationId={openMutation.isPending ? openMutation.variables ?? null : null}
      markingNotificationId={markReadMutation.isPending ? markReadMutation.variables ?? null : null}
      isMarkingAllRead={markAllMutation.isPending}
      actionError={
        openError ??
        (openMutation.error instanceof Error
          ? openMutation.error.message
          : markReadMutation.error instanceof Error
            ? markReadMutation.error.message
            : markAllMutation.error instanceof Error
              ? markAllMutation.error.message
              : null)
      }
      markAllSucceeded={markAllMutation.isSuccess}
      onFilterChange={setFilter}
      onRefresh={() => void query.refetch()}
      onLoadMore={() => void query.fetchNextPage()}
      onOpenNotification={(notification) => {
        setOpenError(null);
        openMutation.reset();
        openMutation.mutate(notification.id);
      }}
      onMarkRead={(notification) => {
        markReadMutation.reset();
        markAllMutation.reset();
        markReadMutation.mutate(notification.id);
      }}
      onMarkAllRead={() => {
        markReadMutation.reset();
        markAllMutation.reset();
        markAllMutation.mutate();
      }}
    />
  );
}
