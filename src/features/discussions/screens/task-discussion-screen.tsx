import React from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ActivityIndicator, FlatList, Text, TextInput, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import type { TaskComment } from "@/contracts/discussions";
import { useAuth } from "@/features/auth/auth-context";
import { sendTaskComment } from "@/features/discussions/api/discussions-api";
import { taskCommentsInfiniteQueryOptions } from "@/features/discussions/query-options";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { queryKeys } from "@/lib/query/keys";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

function flatten(pages: readonly { items: readonly TaskComment[] }[] | undefined): TaskComment[] {
  const comments = new Map<string, TaskComment>();
  for (const page of pages ?? []) for (const item of page.items) comments.set(item.id, item);
  return [...comments.values()];
}

export function TaskDiscussionScreen({ taskId }: { taskId: string }) {
  const { state } = useAuth();
  const queryClient = useQueryClient();
  const userId = state.kind === "authorized" ? state.profile.id : "";
  const authorName = state.kind === "authorized" ? state.profile.fullName : "";
  const enabled = state.kind === "authorized" && isPhase1CapabilityEnabled("taskComments");
  const query = useInfiniteQuery({ ...taskCommentsInfiniteQueryOptions(taskId), enabled });
  const [body, setBody] = React.useState("");
  const mutation = useMutation({
    mutationFn: sendTaskComment,
    onSuccess: async () => {
      setBody("");
      await queryClient.invalidateQueries({ queryKey: queryKeys.discussions.task(taskId, 0) });
    }
  });
  const comments = React.useMemo(() => flatten(query.data?.pages), [query.data?.pages]);

  if (state.kind !== "authorized") return null;
  if (!enabled) return <AppScreen testID="task-comments-gated"><StatusNotice tone="warning">Task comments are prepared but disabled until participant-only read/write checks are recorded.</StatusNotice></AppScreen>;
  return <FlatList data={comments} keyExtractor={(item) => item.id} inverted style={{ flex: 1, backgroundColor: colors.background }} contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.md }} ListHeaderComponent={query.hasNextPage ? <Button label="Load earlier comments" loading={query.isFetchingNextPage} onPress={() => void query.fetchNextPage()} /> : null} renderItem={({ item }) => <View style={{ gap: tokens.space.xs, padding: tokens.space.md, borderRadius: tokens.radius.md, backgroundColor: colors.surface }}><Text style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>{item.authorName}</Text><Text style={{ color: colors.label, fontSize: tokens.type.body }}>{item.body}</Text></View>} ListEmptyComponent={query.isLoading ? <ActivityIndicator accessibilityLabel="Loading comments" color={colors.primary} /> : <Text style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>No comments yet.</Text>} ListFooterComponent={<View style={{ gap: tokens.space.sm }}><TextInput accessibilityLabel="New task comment" value={body} onChangeText={setBody} multiline maxLength={2000} textAlignVertical="top" placeholder="Add a comment" placeholderTextColor={colors.secondaryLabel} style={{ minHeight: 88, padding: tokens.space.md, borderRadius: tokens.radius.md, borderWidth: 1, borderColor: colors.separator, color: colors.label, backgroundColor: colors.surface }} />{mutation.error ? <StatusNotice tone="danger">{mutation.error instanceof SupabaseUserError ? mutation.error.message : mutation.error instanceof Error ? mutation.error.message : "We could not send this comment."}</StatusNotice> : null}<StatusNotice>Comments are sent only while online and are never queued.</StatusNotice><Button label="Send comment" loading={mutation.isPending} disabled={!body.trim()} onPress={() => mutation.mutate({ taskId, authorId: userId, authorName, body })} /></View>} />;
}
