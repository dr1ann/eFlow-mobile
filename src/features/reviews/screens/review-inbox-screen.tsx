import React from "react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { useRouter, type Href } from "expo-router";
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { SubtaskSubmission } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import { pendingSubtaskReviewsQueryOptions, pendingTaskReviewsQueryOptions } from "@/features/reviews/query-options";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

type ReviewInboxItem =
  | { kind: "task"; id: string; title: string; submittedAt: string | null }
  | { kind: "subtask"; id: string; title: string; submittedAt: string | null };

function flatten<T>(pages: readonly { items: readonly T[] }[] | undefined): readonly T[] {
  return (pages ?? []).flatMap((page) => page.items);
}

function combine(taskPages: readonly { items: readonly Task[] }[] | undefined, subtaskPages: readonly { items: readonly SubtaskSubmission[] }[] | undefined): ReviewInboxItem[] {
  return [
    ...flatten(taskPages).map((task) => ({ kind: "task" as const, id: task.id, title: task.title, submittedAt: task.updatedAt })),
    ...flatten(subtaskPages).map((submission) => ({ kind: "subtask" as const, id: submission.subtaskId, title: `Subtask submission · ${submission.submitterName}`, submittedAt: submission.submittedAt }))
  ].sort((left, right) => (right.submittedAt ?? "").localeCompare(left.submittedAt ?? ""));
}

export function ReviewInboxScreen() {
  const { state, can } = useAuth();
  const router = useRouter();
  if (state.kind !== "authorized") return null;
  if (!can("navigation.tasks")) return <AppScreen><StatusNotice tone="danger">Your verified permissions do not allow mobile work reviews.</StatusNotice></AppScreen>;
  return <ReviewInbox userId={state.profile.id} onOpen={(item) => router.push((item.kind === "task" ? `/reviews/tasks/${item.id}` : `/reviews/subtasks/${item.id}`) as Href)} />;
}

function ReviewInbox({ userId, onOpen }: { userId: string; onOpen(item: ReviewInboxItem): void }) {
  const taskQuery = useInfiniteQuery(pendingTaskReviewsQueryOptions(userId));
  const subtaskQuery = useInfiniteQuery(pendingSubtaskReviewsQueryOptions(userId));
  const items = React.useMemo(() => combine(taskQuery.data?.pages, subtaskQuery.data?.pages), [subtaskQuery.data?.pages, taskQuery.data?.pages]);
  const isLoading = taskQuery.isLoading || subtaskQuery.isLoading;
  const isError = taskQuery.isError || subtaskQuery.isError;
  const refresh = (): void => { void taskQuery.refetch(); void subtaskQuery.refetch(); };

  return <FlatList testID="review-inbox" data={items} keyExtractor={(item) => `${item.kind}-${item.id}`} style={{ flex: 1, backgroundColor: colors.background }} contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ flexGrow: 1, padding: tokens.space.lg, gap: tokens.space.md }} refreshControl={<RefreshControl refreshing={taskQuery.isRefetching || subtaskQuery.isRefetching} onRefresh={refresh} tintColor={colors.primary} />} ListHeaderComponent={<View style={{ gap: tokens.space.xs, paddingBottom: tokens.space.sm }}><Text style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>Review inbox</Text><Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>Pending submissions routed to your account by the server.</Text></View>} renderItem={({ item }) => <Pressable accessibilityRole="button" accessibilityLabel={`Open ${item.kind} review: ${item.title}`} onPress={() => onOpen(item)} style={({ pressed }) => ({ minHeight: tokens.touchTarget, padding: tokens.space.lg, gap: tokens.space.xs, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, backgroundColor: colors.surface, opacity: pressed ? 0.78 : 1 })}><Text style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>{item.title}</Text><Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>{item.kind === "task" ? "Task review" : "Subtask review"}</Text></Pressable>} ListEmptyComponent={isLoading ? <ActivityIndicator accessibilityLabel="Loading review inbox" color={colors.primary} /> : isError ? <View style={{ gap: tokens.space.md }}><StatusNotice tone="danger">We could not load pending reviews.</StatusNotice><Button label="Retry reviews" onPress={refresh} /></View> : <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>No pending reviews are available.</Text>} />;
}
