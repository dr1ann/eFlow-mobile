import React from "react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import {
  ActivityIndicator,
  FlatList,
  RefreshControl,
  Text,
  useColorScheme,
  View
} from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { projectPriorityLabel, projectStatusLabel, type ProjectOverview } from "@/contracts/projects";
import { type Task } from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import { TaskListItem } from "@/features/tasks/components/task-list-item";
import { projectTasksInfiniteQueryOptions } from "@/features/tasks/query-options";
import { flattenTaskFeed } from "@/features/tasks/feed";
import { ProjectLifecyclePanel } from "@/features/projects/screens/project-lifecycle-panel";
import { projectDetailQueryOptions } from "@/features/projects/query-options";
import { formatTaskDate } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

interface ProjectDetailViewProps {
  project: ProjectOverview;
  lifecycle?: React.ReactNode;
  linkedTasks?: readonly Task[];
  linkedTasksLoading?: boolean;
  linkedTasksError?: boolean;
  linkedTasksPaused?: boolean;
  canViewLinkedTasks?: boolean;
  hasNextPage?: boolean;
  isFetchingNextPage?: boolean;
  isRefreshing?: boolean;
  onRefresh?(): void;
  onRetryLinkedTasks?(): void;
  onLoadMore?(): void;
  onOpenTask?(taskId: string): void;
}

export function ProjectDetailView({
  project,
  lifecycle,
  linkedTasks = [],
  linkedTasksLoading = false,
  linkedTasksError = false,
  linkedTasksPaused = false,
  canViewLinkedTasks = false,
  hasNextPage = false,
  isFetchingNextPage = false,
  isRefreshing = false,
  onRefresh,
  onRetryLinkedTasks,
  onLoadMore,
  onOpenTask
}: ProjectDetailViewProps) {
  useColorScheme();

  return (
    <FlatList
      testID="project-detail-screen"
      data={canViewLinkedTasks ? linkedTasks : []}
      keyExtractor={(task) => task.id}
      contentInsetAdjustmentBehavior="automatic"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{
        flexGrow: 1,
        padding: tokens.space.lg,
        gap: tokens.space.md
      }}
      refreshControl={
        onRefresh ? (
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        ) : undefined
      }
      ListHeaderComponent={
        <View style={{ gap: tokens.space.lg, paddingBottom: tokens.space.sm }}>
          <View style={{ gap: tokens.space.xs }}>
            <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
              {project.title}
            </Text>
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              {projectStatusLabel(project.status)} · {projectPriorityLabel(project.priority)} priority
            </Text>
          </View>

          <ProjectDetailSection title="Overview">
            <ProjectDetailValue label="Description" value={project.description || "No description provided."} />
            <ProjectDetailValue label="Program" value={project.programTitle ?? "Not linked to a program"} />
          </ProjectDetailSection>

          <ProjectDetailSection title="Schedule">
            <ProjectDetailValue label="Start date" value={formatTaskDate(project.startDate)} />
            <ProjectDetailValue label="Target date" value={formatTaskDate(project.targetDate)} />
            <ProjectDetailValue label="Last updated" value={formatTaskDate(project.updatedAt)} />
          </ProjectDetailSection>

          {lifecycle ?? (
            <StatusNotice>
              Members, milestones, work rollups, activity, and project changes stay unavailable until their
              permission-scoped contracts are verified. This screen only shows the authorized project summary.
            </StatusNotice>
          )}

          <ProjectDetailSection title="Related work">
            {!canViewLinkedTasks ? (
              <StatusNotice>
                Related work is unavailable for this mobile access. Individual task access remains separately
                authorized.
              </StatusNotice>
            ) : null}
            {linkedTasksLoading ? (
              <View style={{ alignItems: "center", gap: tokens.space.sm }}>
                <ActivityIndicator accessibilityLabel="Loading related tasks" color={colors.primary} />
                <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                  Loading related work…
                </Text>
              </View>
            ) : null}
            {linkedTasksError ? (
              <View style={{ gap: tokens.space.md }}>
                <StatusNotice tone="danger">
                  We could not load related work. It may be unavailable, or your access may have changed.
                </StatusNotice>
                {onRetryLinkedTasks ? <Button label="Retry related work" onPress={onRetryLinkedTasks} /> : null}
              </View>
            ) : null}
            {linkedTasksPaused ? (
              <StatusNotice tone="warning">
                You are offline. Showing cached related work when available; reconnect to refresh.
              </StatusNotice>
            ) : null}
            {canViewLinkedTasks && !linkedTasksLoading && !linkedTasksError ? (
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
                {linkedTasks.length === 0
                  ? "No related tasks are visible for this project."
                  : `Showing ${linkedTasks.length} loaded related task${linkedTasks.length === 1 ? "" : "s"}. This is not an organization total.`}
              </Text>
            ) : null}
          </ProjectDetailSection>
        </View>
      }
      renderItem={({ item }) =>
        onOpenTask ? <TaskListItem task={item} onPress={() => onOpenTask(item.id)} /> : null
      }
      ListFooterComponent={
        canViewLinkedTasks && hasNextPage && onLoadMore ? (
          <View style={{ paddingTop: tokens.space.sm }}>
            <Button
              label="Load more related tasks"
              loading={isFetchingNextPage}
              onPress={onLoadMore}
            />
          </View>
        ) : null
      }
    />
  );
}

function ProjectDetailSection({
  title,
  children
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <View
      style={{
        gap: tokens.space.md,
        padding: tokens.space.lg,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: colors.separator,
        backgroundColor: colors.surface
      }}
    >
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        {title}
      </Text>
      {children}
    </View>
  );
}

function ProjectDetailValue({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ gap: tokens.space.xs }}>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
        {label}
      </Text>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, lineHeight: 22 }}>
        {value}
      </Text>
    </View>
  );
}

export function ProjectDetailScreen({ projectId }: { projectId: string }) {
  const router = useRouter();
  const { can } = useAuth();
  const projectQuery = useQuery(projectDetailQueryOptions(projectId));
  const canViewLinkedTasks = can("navigation.tasks");
  const linkedTasksQuery = useInfiniteQuery({
    ...projectTasksInfiniteQueryOptions(projectId),
    enabled: canViewLinkedTasks && projectQuery.isSuccess && projectQuery.data !== null
  });
  const linkedTasks = React.useMemo(
    () => flattenTaskFeed(linkedTasksQuery.data?.pages),
    [linkedTasksQuery.data?.pages]
  );

  if (projectQuery.isLoading) {
    return (
      <AppScreen testID="project-detail-loading">
        <ActivityIndicator accessibilityLabel="Loading project" color={colors.primary} />
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Loading project…
        </Text>
      </AppScreen>
    );
  }

  if (projectQuery.isError) {
    return (
      <AppScreen testID="project-detail-error">
        <StatusNotice tone="danger">
          We could not open this project. It may be unavailable, or your access may have changed.
        </StatusNotice>
        <Button label="Try again" onPress={() => void projectQuery.refetch()} />
      </AppScreen>
    );
  }

  if (!projectQuery.data) {
    return (
      <AppScreen testID="project-detail-unavailable">
        <StatusNotice tone="danger">
          This project is unavailable or you do not have access to it.
        </StatusNotice>
      </AppScreen>
    );
  }

  const refresh = (): void => {
    void projectQuery.refetch();
    if (canViewLinkedTasks) void linkedTasksQuery.refetch();
  };

  return (
    <ProjectDetailView
      project={projectQuery.data}
      lifecycle={<ProjectLifecyclePanel project={projectQuery.data} />}
      linkedTasks={linkedTasks}
      linkedTasksLoading={canViewLinkedTasks && linkedTasksQuery.isLoading}
      linkedTasksError={canViewLinkedTasks && linkedTasksQuery.isError}
      linkedTasksPaused={canViewLinkedTasks && linkedTasksQuery.fetchStatus === "paused"}
      canViewLinkedTasks={canViewLinkedTasks}
      hasNextPage={Boolean(linkedTasksQuery.hasNextPage)}
      isFetchingNextPage={linkedTasksQuery.isFetchingNextPage}
      isRefreshing={projectQuery.isRefetching || linkedTasksQuery.isRefetching}
      onRefresh={refresh}
      onRetryLinkedTasks={() => void linkedTasksQuery.refetch()}
      onLoadMore={() => void linkedTasksQuery.fetchNextPage()}
      onOpenTask={(taskId) =>
        router.push({ pathname: "/tasks/[task-id]", params: { "task-id": taskId } })
      }
    />
  );
}
