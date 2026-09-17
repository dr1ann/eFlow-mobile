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
  SUBTASK_FILTERS,
  subtaskStatusLabel,
  type Subtask,
  type SubtaskFilter
} from "@/contracts/subtasks";
import {
  TASK_FILTERS,
  type Task,
  type TaskFilter
} from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import { TaskListItem } from "@/features/tasks/components/task-list-item";
import {
  matchesDeadlineFilter,
  type DeadlineFilter
} from "@/features/tasks/deadlines";
import {
  leadingTasksInfiniteQueryOptions,
  myTasksInfiniteQueryOptions
} from "@/features/tasks/query-options";
import { flattenTaskFeed } from "@/features/tasks/feed";
import { formatTaskDate, TASK_FILTER_LABELS } from "@/features/tasks/presentation";
import { taskDeadline } from "@/features/tasks/selectors";
import {
  mySubtasksInfiniteQueryOptions,
  type SubtaskFeedPage
} from "@/features/subtasks/query-options";
import { sortSubtasksByDeadline } from "@/features/subtasks/selectors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export const WORK_SCOPES = ["tasks", "subtasks", "leading"] as const;
export type WorkScope = (typeof WORK_SCOPES)[number];

const WORK_SCOPE_LABELS: Record<WorkScope, string> = {
  tasks: "My Tasks",
  subtasks: "My Subtasks",
  leading: "Work I am Leading"
};

const SUBTASK_FILTER_LABELS: Record<SubtaskFilter, string> = {
  active: "Active",
  review: "Awaiting review",
  changes_requested: "Changes requested",
  completed: "Completed",
  history: "History"
};

const DEADLINE_FILTERS: readonly { value: DeadlineFilter; label: string }[] = [
  { value: "all", label: "All dates" },
  { value: "overdue", label: "Overdue" },
  { value: "due_soon", label: "Due in 7 days" }
];

export { flattenTaskFeed } from "@/features/tasks/feed";

export function flattenSubtaskFeed(pages: readonly SubtaskFeedPage[] | undefined): Subtask[] {
  const subtasks = new Map<string, Subtask>();
  for (const page of pages ?? []) {
    for (const subtask of page.items) subtasks.set(subtask.id, subtask);
  }
  return sortSubtasksByDeadline([...subtasks.values()]);
}

export function filterTasksForDeadline(
  tasks: readonly Task[],
  filter: DeadlineFilter,
  now: Date
): Task[] {
  return tasks.filter((task) => matchesDeadlineFilter(taskDeadline(task), filter, now));
}

export function filterSubtasksForDeadline(
  subtasks: readonly Subtask[],
  filter: DeadlineFilter,
  now: Date
): Subtask[] {
  return subtasks.filter((subtask) => matchesDeadlineFilter(subtask.dueDate, filter, now));
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
  scope?: WorkScope;
  deadlineFilter?: DeadlineFilter;
  onScopeChange?(scope: WorkScope): void;
  onDeadlineFilterChange?(filter: DeadlineFilter): void;
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
  onOpenTask,
  scope = "tasks",
  deadlineFilter = "all",
  onScopeChange = () => undefined,
  onDeadlineFilterChange = () => undefined
}: WorkScreenViewProps) {
  return (
    <WorkList
      testID="work-task-list"
      items={tasks}
      itemLabel="task"
      title={scope === "leading" ? "Work I am leading" : "My work"}
      description={
        scope === "leading"
          ? "Tasks where the stored assignment makes you the effective Task Lead."
          : "Tasks returned by your authenticated Supabase access."
      }
      scope={scope}
      deadlineFilter={deadlineFilter}
      filters={<TaskFilters filter={filter} onFilterChange={onFilterChange} />}
      isLoading={isLoading}
      isRefreshing={isRefreshing}
      isError={isError}
      isPaused={isPaused}
      hasNextPage={hasNextPage}
      isFetchingNextPage={isFetchingNextPage}
      onScopeChange={onScopeChange}
      onDeadlineFilterChange={onDeadlineFilterChange}
      onRefresh={onRefresh}
      onLoadMore={onLoadMore}
      renderItem={(task) => <TaskListItem task={task} onPress={() => onOpenTask(task.id)} />}
    />
  );
}

interface SubtaskWorkScreenViewProps {
  subtasks: readonly Subtask[];
  filter: SubtaskFilter;
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  deadlineFilter: DeadlineFilter;
  onFilterChange(filter: SubtaskFilter): void;
  onDeadlineFilterChange(filter: DeadlineFilter): void;
  onScopeChange(scope: WorkScope): void;
  onRefresh(): void;
  onLoadMore(): void;
  onOpenSubtask(subtaskId: string): void;
}

export function SubtaskWorkScreenView({
  subtasks,
  filter,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  deadlineFilter,
  onFilterChange,
  onDeadlineFilterChange,
  onScopeChange,
  onRefresh,
  onLoadMore,
  onOpenSubtask
}: SubtaskWorkScreenViewProps) {
  return (
    <WorkList
      testID="work-subtask-list"
      items={subtasks}
      itemLabel="subtask"
      title="My subtasks"
      description="Subtasks assigned directly to you by the authenticated work contract."
      scope="subtasks"
      deadlineFilter={deadlineFilter}
      filters={<SubtaskFilters filter={filter} onFilterChange={onFilterChange} />}
      isLoading={isLoading}
      isRefreshing={isRefreshing}
      isError={isError}
      isPaused={isPaused}
      hasNextPage={hasNextPage}
      isFetchingNextPage={isFetchingNextPage}
      onScopeChange={onScopeChange}
      onDeadlineFilterChange={onDeadlineFilterChange}
      onRefresh={onRefresh}
      onLoadMore={onLoadMore}
      renderItem={(subtask) => (
        <SubtaskWorkListItem subtask={subtask} onPress={() => onOpenSubtask(subtask.id)} />
      )}
    />
  );
}

interface WorkListProps<Item extends { id: string }> {
  testID: string;
  items: readonly Item[];
  itemLabel: string;
  title: string;
  description: string;
  scope: WorkScope;
  deadlineFilter: DeadlineFilter;
  filters: React.ReactNode;
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  onScopeChange(scope: WorkScope): void;
  onDeadlineFilterChange(filter: DeadlineFilter): void;
  onRefresh(): void;
  onLoadMore(): void;
  renderItem(item: Item): React.ReactElement;
}

function WorkList<Item extends { id: string }>({
  testID,
  items,
  itemLabel,
  title,
  description,
  scope,
  deadlineFilter,
  filters,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  onScopeChange,
  onDeadlineFilterChange,
  onRefresh,
  onLoadMore,
  renderItem
}: WorkListProps<Item>) {
  useColorScheme();
  const pluralLabel = `${itemLabel}${items.length === 1 ? "" : "s"}`;

  return (
    <FlatList
      testID={testID}
      data={items}
      keyExtractor={(item) => item.id}
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
            <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
              {title}
            </Text>
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
              {description}
            </Text>
          </View>

          <WorkScopePicker scope={scope} onScopeChange={onScopeChange} />
          {filters}
          <DeadlineFilters
            deadlineFilter={deadlineFilter}
            onDeadlineFilterChange={onDeadlineFilterChange}
          />

          <StatusNotice>
            Due dates are calendar dates on this device. Timestamp deadlines use the device time zone;
            “Due in 7 days” includes today and the next seven calendar days. Deadline views show loaded
            authorized work only.
          </StatusNotice>

          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
            Showing {items.length} loaded {pluralLabel}. This is not an organization total.
          </Text>

          {scope !== "subtasks" ? (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
              The Waiting filter shows only server-persisted waiting-for-assignment work. Dependency
              readiness is not inferred from a partial list.
            </Text>
          ) : null}

          {isPaused ? (
            <StatusNotice tone="warning">
              You are offline. Showing cached work when available; reconnect to refresh.
            </StatusNotice>
          ) : null}

          {isError && items.length > 0 ? (
            <StatusNotice tone="warning">
              Refresh failed. The work list below may be out of date.
            </StatusNotice>
          ) : null}
        </View>
      }
      renderItem={({ item }) => renderItem(item)}
      ListEmptyComponent={
        <View style={{ flex: 1, minHeight: 240, alignItems: "center", justifyContent: "center", gap: tokens.space.md }}>
          {isLoading ? (
            <>
              <ActivityIndicator accessibilityLabel={`Loading ${pluralLabel}`} color={colors.primary} />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                Loading your {pluralLabel}…
              </Text>
            </>
          ) : isError ? (
            <>
              <StatusNotice tone="danger">
                We could not load your {pluralLabel}. Check your connection or access and try again.
              </StatusNotice>
              <Button label="Try again" onPress={onRefresh} />
            </>
          ) : hasNextPage ? (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, textAlign: "center" }}>
              No matching {pluralLabel} are loaded yet. Load more to check later authorized pages.
            </Text>
          ) : (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              No {pluralLabel} match these filters.
            </Text>
          )}
        </View>
      }
      ListFooterComponent={
        hasNextPage ? (
          <View style={{ paddingTop: tokens.space.sm }}>
            <Button
              label={`Load more ${pluralLabel}`}
              loading={isFetchingNextPage}
              onPress={onLoadMore}
            />
          </View>
        ) : null
      }
    />
  );
}

function WorkScopePicker({
  scope,
  onScopeChange
}: {
  scope: WorkScope;
  onScopeChange(scope: WorkScope): void;
}) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: tokens.space.sm }}>
      {WORK_SCOPES.map((candidate) => (
        <SelectionChip
          key={candidate}
          label={WORK_SCOPE_LABELS[candidate]}
          selected={candidate === scope}
          accessibilityLabel={`Show ${WORK_SCOPE_LABELS[candidate]}`}
          onPress={() => onScopeChange(candidate)}
        />
      ))}
    </ScrollView>
  );
}

function TaskFilters({
  filter,
  onFilterChange
}: {
  filter: TaskFilter;
  onFilterChange(filter: TaskFilter): void;
}) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: tokens.space.sm }}>
      {TASK_FILTERS.map((candidate) => (
        <SelectionChip
          key={candidate}
          label={TASK_FILTER_LABELS[candidate]}
          selected={candidate === filter}
          accessibilityLabel={`Filter tasks by ${TASK_FILTER_LABELS[candidate]}`}
          onPress={() => onFilterChange(candidate)}
        />
      ))}
    </ScrollView>
  );
}

function SubtaskFilters({
  filter,
  onFilterChange
}: {
  filter: SubtaskFilter;
  onFilterChange(filter: SubtaskFilter): void;
}) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: tokens.space.sm }}>
      {SUBTASK_FILTERS.map((candidate) => (
        <SelectionChip
          key={candidate}
          label={SUBTASK_FILTER_LABELS[candidate]}
          selected={candidate === filter}
          accessibilityLabel={`Filter subtasks by ${SUBTASK_FILTER_LABELS[candidate]}`}
          onPress={() => onFilterChange(candidate)}
        />
      ))}
    </ScrollView>
  );
}

function DeadlineFilters({
  deadlineFilter,
  onDeadlineFilterChange
}: {
  deadlineFilter: DeadlineFilter;
  onDeadlineFilterChange(filter: DeadlineFilter): void;
}) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: tokens.space.sm }}>
      {DEADLINE_FILTERS.map((candidate) => (
        <SelectionChip
          key={candidate.value}
          label={candidate.label}
          selected={candidate.value === deadlineFilter}
          accessibilityLabel={`Show ${candidate.label.toLowerCase()} work`}
          onPress={() => onDeadlineFilterChange(candidate.value)}
        />
      ))}
    </ScrollView>
  );
}

function SelectionChip({
  label,
  selected,
  accessibilityLabel,
  onPress
}: {
  label: string;
  selected: boolean;
  accessibilityLabel: string;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ selected }}
      onPress={onPress}
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
        {label}
      </Text>
    </Pressable>
  );
}

function SubtaskWorkListItem({
  subtask,
  onPress
}: {
  subtask: Subtask;
  onPress(): void;
}) {
  const dueDate = formatTaskDate(subtask.dueDate);

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Open ${subtask.title}. ${subtaskStatusLabel(subtask.status)}. ${dueDate}.`}
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
          {subtask.title}
        </Text>
        <Text selectable style={{ color: colors.primary, fontSize: tokens.type.caption, fontWeight: "700" }}>
          {subtask.percentComplete}%
        </Text>
      </View>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {subtaskStatusLabel(subtask.status)} · {dueDate}
      </Text>
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
  const [scope, setScope] = React.useState<WorkScope>("tasks");
  const [taskFilter, setTaskFilter] = React.useState<TaskFilter>("active");
  const [subtaskFilter, setSubtaskFilter] = React.useState<SubtaskFilter>("active");
  const [deadlineFilter, setDeadlineFilter] = React.useState<DeadlineFilter>("all");
  const tasksQuery = useInfiniteQuery({
    ...myTasksInfiniteQueryOptions(userId, taskFilter),
    enabled: scope === "tasks"
  });
  const leadingQuery = useInfiniteQuery({
    ...leadingTasksInfiniteQueryOptions(userId, taskFilter),
    enabled: scope === "leading"
  });
  const subtasksQuery = useInfiniteQuery({
    ...mySubtasksInfiniteQueryOptions(userId, subtaskFilter),
    enabled: scope === "subtasks"
  });
  const now = new Date();
  const tasks = filterTasksForDeadline(flattenTaskFeed(tasksQuery.data?.pages), deadlineFilter, now);
  const leadingTasks = filterTasksForDeadline(
    flattenTaskFeed(leadingQuery.data?.pages),
    deadlineFilter,
    now
  );
  const subtasks = filterSubtasksForDeadline(
    flattenSubtaskFeed(subtasksQuery.data?.pages),
    deadlineFilter,
    now
  );

  const openTask = (taskId: string): void => {
    router.push({ pathname: "/tasks/[task-id]", params: { "task-id": taskId } });
  };
  const openSubtask = (subtaskId: string): void => {
    router.push({ pathname: "/subtasks/[subtask-id]", params: { "subtask-id": subtaskId } });
  };

  if (scope === "subtasks") {
    return (
      <SubtaskWorkScreenView
        subtasks={subtasks}
        filter={subtaskFilter}
        deadlineFilter={deadlineFilter}
        isLoading={subtasksQuery.isLoading}
        isRefreshing={subtasksQuery.isRefetching}
        isError={subtasksQuery.isError}
        isPaused={subtasksQuery.fetchStatus === "paused"}
        hasNextPage={Boolean(subtasksQuery.hasNextPage)}
        isFetchingNextPage={subtasksQuery.isFetchingNextPage}
        onFilterChange={setSubtaskFilter}
        onDeadlineFilterChange={setDeadlineFilter}
        onScopeChange={setScope}
        onRefresh={() => void subtasksQuery.refetch()}
        onLoadMore={() => void subtasksQuery.fetchNextPage()}
        onOpenSubtask={openSubtask}
      />
    );
  }

  const isLeading = scope === "leading";
  const query = isLeading ? leadingQuery : tasksQuery;
  return (
    <WorkScreenView
      tasks={isLeading ? leadingTasks : tasks}
      filter={taskFilter}
      scope={scope}
      deadlineFilter={deadlineFilter}
      isLoading={query.isLoading}
      isRefreshing={query.isRefetching}
      isError={query.isError}
      isPaused={query.fetchStatus === "paused"}
      hasNextPage={Boolean(query.hasNextPage)}
      isFetchingNextPage={query.isFetchingNextPage}
      onFilterChange={setTaskFilter}
      onDeadlineFilterChange={setDeadlineFilter}
      onScopeChange={setScope}
      onRefresh={() => void query.refetch()}
      onLoadMore={() => void query.fetchNextPage()}
      onOpenTask={openTask}
    />
  );
}
