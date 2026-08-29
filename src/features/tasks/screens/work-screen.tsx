import React from "react";
import { useInfiniteQuery } from "@tanstack/react-query";
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

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  TASK_FILTERS,
  taskStatusLabel,
  type Task,
  type TaskFilter
} from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import {
  myTasksInfiniteQueryOptions,
  type TaskFeedPage
} from "@/features/tasks/query-options";
import { formatTaskDate, TASK_FILTER_LABELS } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function flattenTaskFeed(pages: readonly TaskFeedPage[] | undefined): Task[] {
  const tasks = new Map<string, Task>();
  for (const page of pages ?? []) {
    for (const task of page.items) tasks.set(task.id, task);
  }
  return [...tasks.values()];
}

interface WorkScreenViewProps {
  tasks: readonly Task[];
  filter: TaskFilter;
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  onFilterChange(filter: TaskFilter): void;
  onRefresh(): void;
  onLoadMore(): void;
  onOpenTask(taskId: string): void;
}

export function WorkScreenView({
  tasks,
  filter,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  onFilterChange,
  onRefresh,
  onLoadMore,
  onOpenTask
}: WorkScreenViewProps) {
  useColorScheme();

  return (
    <FlatList
      testID="work-task-list"
      data={tasks}
      keyExtractor={(task) => task.id}
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
              My work
            </Text>
            <Text
              selectable
              style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}
            >
              Tasks returned by your authenticated Supabase access.
            </Text>
          </View>

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ gap: tokens.space.sm }}
          >
            {TASK_FILTERS.map((candidate) => {
              const selected = candidate === filter;
              return (
                <Pressable
                  key={candidate}
                  accessibilityRole="button"
                  accessibilityLabel={`Filter tasks by ${TASK_FILTER_LABELS[candidate]}`}
                  accessibilityState={{ selected }}
                  onPress={() => onFilterChange(candidate)}
                  style={({ pressed }) => ({
                    minHeight: tokens.touchTarget,
                    justifyContent: "center",
                    paddingHorizontal: tokens.space.md,
                    borderRadius: tokens.radius.pill,
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
                    {TASK_FILTER_LABELS[candidate]}
                  </Text>
                </Pressable>
              );
            })}
          </ScrollView>

          <StatusNotice tone="warning">
            Evidence upload and review submission are disabled until task-scoped Storage policies are deployed. You can test local evidence selection from a subtask without sending the file.
          </StatusNotice>

          {isPaused ? (
            <StatusNotice tone="warning">
              You are offline. Showing cached work when available; reconnect to refresh.
            </StatusNotice>
          ) : null}

          {isError && tasks.length > 0 ? (
            <StatusNotice tone="warning">
              Refresh failed. The task list below may be out of date.
            </StatusNotice>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <TaskListItem task={item} onPress={() => onOpenTask(item.id)} />
      )}
      ListEmptyComponent={
        <View style={{ flex: 1, minHeight: 240, alignItems: "center", justifyContent: "center", gap: tokens.space.md }}>
          {isLoading ? (
            <>
              <ActivityIndicator accessibilityLabel="Loading tasks" color={colors.primary} />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                Loading your tasks…
              </Text>
            </>
          ) : isError ? (
            <>
              <StatusNotice tone="danger">
                We could not load your tasks. Check your connection or access and try again.
              </StatusNotice>
              <Button label="Try again" onPress={onRefresh} />
            </>
          ) : (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              No tasks match this filter.
            </Text>
          )}
        </View>
      }
      ListFooterComponent={
        hasNextPage ? (
          <View style={{ paddingTop: tokens.space.sm }}>
            <Button
              label="Load more tasks"
              loading={isFetchingNextPage}
              onPress={onLoadMore}
            />
          </View>
        ) : null
      }
    />
  );
}

function TaskListItem({ task, onPress }: { task: Task; onPress(): void }) {
  const dueDate = formatTaskDate(task.deadline ?? task.dueDate);

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Open ${task.title}. ${taskStatusLabel(task.status)}. ${dueDate}.`}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: tokens.touchTarget,
        gap: tokens.space.sm,
        padding: tokens.space.lg,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: colors.separator,
        backgroundColor: colors.surface,
        opacity: pressed ? 0.78 : 1
      })}
    >
      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: tokens.space.md }}>
        <Text
          selectable
          numberOfLines={2}
          style={{ flex: 1, color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}
        >
          {task.title}
        </Text>
        <Text
          selectable
          style={{ color: colors.primary, fontSize: tokens.type.caption, fontWeight: "700" }}
        >
          {task.percentComplete}%
        </Text>
      </View>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {taskStatusLabel(task.status)} · {dueDate}
      </Text>
      {task.projectTitle ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
          {task.projectTitle}
        </Text>
      ) : null}
    </Pressable>
  );
}

export function WorkScreen() {
  const { state, can } = useAuth();
  if (state.kind !== "authorized") return null;

  if (!can("navigation.tasks")) {
    return (
      <AppScreen testID="work-access-denied">
        <StatusNotice tone="danger">
          Your verified permissions do not allow access to mobile tasks.
        </StatusNotice>
      </AppScreen>
    );
  }

  return <AuthorizedWorkScreen userId={state.profile.id} />;
}

function AuthorizedWorkScreen({ userId }: { userId: string }) {
  const router = useRouter();
  const [filter, setFilter] = React.useState<TaskFilter>("active");
  const query = useInfiniteQuery(myTasksInfiniteQueryOptions(userId, filter));
  const tasks = React.useMemo(() => flattenTaskFeed(query.data?.pages), [query.data?.pages]);

  return (
    <WorkScreenView
      tasks={tasks}
      filter={filter}
      isLoading={query.isLoading}
      isRefreshing={query.isRefetching}
      isError={query.isError}
      isPaused={query.fetchStatus === "paused"}
      hasNextPage={query.hasNextPage}
      isFetchingNextPage={query.isFetchingNextPage}
      onFilterChange={setFilter}
      onRefresh={() => void query.refetch()}
      onLoadMore={() => void query.fetchNextPage()}
      onOpenTask={(taskId) =>
        router.push({ pathname: "/tasks/[task-id]", params: { "task-id": taskId } })
      }
    />
  );
}
