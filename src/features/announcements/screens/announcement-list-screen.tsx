import React from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { Announcement } from "@/contracts/announcements";
import { useAuth } from "@/features/auth/auth-context";
import { markAnnouncementRead } from "@/features/announcements/api/announcements-api";
import { announcementsInfiniteQueryOptions } from "@/features/announcements/query-options";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

function flatten(pages: readonly { items: readonly Announcement[] }[] | undefined): Announcement[] {
  const unique = new Map<string, Announcement>();
  for (const page of pages ?? []) for (const item of page.items) unique.set(item.id, item);
  return [...unique.values()];
}

export function AnnouncementListScreen() {
  const { state } = useAuth();
  const queryClient = useQueryClient();
  const userId = state.kind === "authorized" ? state.profile.id : "";
  const enabled = state.kind === "authorized" && isPhase1CapabilityEnabled("announcementReads");
  const query = useInfiniteQuery({ ...announcementsInfiniteQueryOptions(userId), enabled });
  const markRead = useMutation({
    mutationFn: (id: string) => markAnnouncementRead(id, userId),
    onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["announcements"] }); }
  });
  const announcements = React.useMemo(() => flatten(query.data?.pages), [query.data?.pages]);

  if (state.kind !== "authorized") return null;
  if (!enabled) return <AppScreen testID="announcements-gated"><StatusNotice tone="warning">Announcements are prepared but disabled until recipient audience and expiry checks are recorded.</StatusNotice></AppScreen>;
  return <FlatList data={announcements} keyExtractor={(item) => item.id} style={{ flex: 1, backgroundColor: colors.background }} contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ flexGrow: 1, padding: tokens.space.lg, gap: tokens.space.md }} refreshControl={<RefreshControl refreshing={query.isRefetching && !query.isLoading} onRefresh={() => void query.refetch()} tintColor={colors.primary} />} ListHeaderComponent={<View style={{ gap: tokens.space.xs, paddingBottom: tokens.space.sm }}><Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Announcements</Text><Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>Published notices returned for your signed-in audience.</Text></View>} renderItem={({ item }) => <AnnouncementItem announcement={item} onRead={() => markRead.mutate(item.id)} busy={markRead.isPending && markRead.variables === item.id} />} ListEmptyComponent={query.isLoading ? <ActivityIndicator accessibilityLabel="Loading announcements" color={colors.primary} /> : query.isError ? <StatusNotice tone="danger">We could not load announcements. Try again.</StatusNotice> : <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>No announcements are available.</Text>} ListFooterComponent={query.hasNextPage ? <Button label="Load more announcements" loading={query.isFetchingNextPage} onPress={() => void query.fetchNextPage()} /> : null} />;
}

function AnnouncementItem({ announcement, onRead, busy }: { announcement: Announcement; onRead(): void; busy: boolean }) {
  const [expanded, setExpanded] = React.useState(false);
  return <View style={{ gap: tokens.space.sm, padding: tokens.space.lg, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, backgroundColor: colors.surface }}><Pressable accessibilityRole="button" accessibilityLabel={`Open announcement ${announcement.title}`} onPress={() => setExpanded((value) => !value)}><Text style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>{announcement.title}</Text><Text numberOfLines={expanded ? undefined : 2} style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>{announcement.body}</Text></Pressable><Button label="Mark announcement read" variant="secondary" loading={busy} onPress={onRead} /></View>;
}
