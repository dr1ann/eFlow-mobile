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
  TextInput,
  useColorScheme,
  View
} from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  PROJECT_FILTERS,
  projectPriorityLabel,
  projectStatusLabel,
  type ProjectFilter,
  type ProjectOverview
} from "@/contracts/projects";
import { useAuth } from "@/features/auth/auth-context";
import { isPhase2CapabilityEnabled } from "@/lib/phase-2/capabilities";
import { canUsePhase2OperationalCapability } from "@/lib/phase-2/permissions";
import { formatTaskDate } from "@/features/tasks/presentation";
import {
  projectsInfiniteQueryOptions,
  type ProjectFeedPage
} from "@/features/projects/query-options";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

const PROJECT_FILTER_LABELS: Record<ProjectFilter, string> = {
  all: "All",
  planning: "Planning",
  active: "Active",
  on_hold: "On hold",
  completed: "Completed",
  archived: "Archived"
};

export function flattenProjectFeed(
  pages: readonly ProjectFeedPage[] | undefined
): ProjectOverview[] {
  const projects = new Map<string, ProjectOverview>();
  for (const page of pages ?? []) {
    for (const project of page.items) projects.set(project.id, project);
  }
  return [...projects.values()];
}

interface ProjectListScreenViewProps {
  projects: readonly ProjectOverview[];
  filter: ProjectFilter;
  search: string;
  isLoading: boolean;
  isRefreshing: boolean;
  isError: boolean;
  isPaused: boolean;
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
  canCreateProject?: boolean;
  onFilterChange(filter: ProjectFilter): void;
  onSearchChange(search: string): void;
  onRefresh(): void;
  onLoadMore(): void;
  onOpenProject(projectId: string): void;
  onCreateProject?(): void;
}

export function ProjectListScreenView({
  projects,
  filter,
  search,
  isLoading,
  isRefreshing,
  isError,
  isPaused,
  hasNextPage,
  isFetchingNextPage,
  canCreateProject = false,
  onFilterChange,
  onSearchChange,
  onRefresh,
  onLoadMore,
  onOpenProject,
  onCreateProject
}: ProjectListScreenViewProps) {
  useColorScheme();

  return (
    <FlatList
      testID="project-list-screen"
      data={projects}
      keyExtractor={(project) => project.id}
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
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
              Projects
            </Text>
            <Text
              selectable
              style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}
            >
              Project summaries returned by your authenticated eFlow access.
            </Text>
          </View>

          {canCreateProject && onCreateProject ? (
            <Button label="Create project" onPress={onCreateProject} />
          ) : null}

          <TextInput
            accessibilityLabel="Search projects"
            value={search}
            onChangeText={onSearchChange}
            placeholder="Search project titles"
            placeholderTextColor={colors.secondaryLabel}
            autoCapitalize="none"
            autoCorrect={false}
            maxLength={100}
            style={{
              minHeight: tokens.touchTarget,
              paddingHorizontal: tokens.space.md,
              borderRadius: tokens.radius.md,
              borderCurve: "continuous",
              borderWidth: 1,
              borderColor: colors.separator,
              color: colors.label,
              backgroundColor: colors.surface,
              fontSize: tokens.type.body
            }}
          />

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ gap: tokens.space.sm }}
          >
            {PROJECT_FILTERS.map((candidate) => {
              const selected = candidate === filter;
              return (
                <Pressable
                  key={candidate}
                  accessibilityRole="button"
                  accessibilityLabel={`Filter projects by ${PROJECT_FILTER_LABELS[candidate]}`}
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
                    {PROJECT_FILTER_LABELS[candidate]}
                  </Text>
                </Pressable>
              );
            })}
          </ScrollView>

          <StatusNotice>
            Project updates, membership changes, and milestone changes remain unavailable until their
            atomic backend contracts are verified.
          </StatusNotice>

          {isPaused ? (
            <StatusNotice tone="warning">
              You are offline. Showing cached project summaries when available; reconnect to refresh.
            </StatusNotice>
          ) : null}

          {isError && projects.length > 0 ? (
            <StatusNotice tone="warning">
              Refresh failed. The project summaries below may be out of date.
            </StatusNotice>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <ProjectListItem project={item} onPress={() => onOpenProject(item.id)} />
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
              <ActivityIndicator accessibilityLabel="Loading projects" color={colors.primary} />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                Loading projects…
              </Text>
            </>
          ) : isError ? (
            <>
              <StatusNotice tone="danger">
                We could not load projects. Check your connection or access and try again.
              </StatusNotice>
              <Button label="Try again" onPress={onRefresh} />
            </>
          ) : (
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              No projects match this filter.
            </Text>
          )}
        </View>
      }
      ListFooterComponent={
        hasNextPage ? (
          <View style={{ paddingTop: tokens.space.sm }}>
            <Button
              label="Load more projects"
              loading={isFetchingNextPage}
              onPress={onLoadMore}
            />
          </View>
        ) : null
      }
    />
  );
}

function ProjectListItem({
  project,
  onPress
}: {
  project: ProjectOverview;
  onPress(): void;
}) {
  const targetDate = formatTaskDate(project.targetDate);

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Open project ${project.title}. ${projectStatusLabel(project.status)}. Target ${targetDate}.`}
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
          {project.title}
        </Text>
        <Text
          selectable
          style={{ color: colors.primary, fontSize: tokens.type.caption, fontWeight: "700" }}
        >
          {projectStatusLabel(project.status)}
        </Text>
      </View>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {projectPriorityLabel(project.priority)} priority · Target {targetDate}
      </Text>
      {project.programTitle ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
          {project.programTitle}
        </Text>
      ) : null}
    </Pressable>
  );
}

export function ProjectListScreen() {
  const { state, can } = useAuth();
  if (state.kind !== "authorized") return null;

  if (!can("navigation.projects")) {
    return (
      <AppScreen testID="projects-access-denied">
        <StatusNotice tone="danger">
          Your verified permissions do not allow access to mobile projects.
        </StatusNotice>
      </AppScreen>
    );
  }

  return <AuthorizedProjectListScreen userId={state.profile.id} />;
}

function AuthorizedProjectListScreen({ userId }: { userId: string }) {
  const router = useRouter();
  const { state } = useAuth();
  const [filter, setFilter] = React.useState<ProjectFilter>("all");
  const [search, setSearch] = React.useState("");
  const query = useInfiniteQuery(projectsInfiniteQueryOptions(userId, filter, search));
  const projects = React.useMemo(
    () => flattenProjectFeed(query.data?.pages),
    [query.data?.pages]
  );

  return (
    <ProjectListScreenView
      projects={projects}
      filter={filter}
      search={search}
      isLoading={query.isLoading}
      isRefreshing={query.isRefetching}
      isError={query.isError}
      isPaused={query.fetchStatus === "paused"}
      hasNextPage={query.hasNextPage ?? false}
      isFetchingNextPage={query.isFetchingNextPage}
      canCreateProject={
        state.kind === "authorized" &&
        canUsePhase2OperationalCapability(
          state.profile,
          "projects.create",
          "projectCreate",
          isPhase2CapabilityEnabled
        )
      }
      onFilterChange={setFilter}
      onSearchChange={setSearch}
      onRefresh={() => void query.refetch()}
      onLoadMore={() => void query.fetchNextPage()}
      onOpenProject={(projectId) =>
        router.push({ pathname: "/projects/[project-id]", params: { "project-id": projectId } })
      }
      onCreateProject={() => router.push("/projects/create")}
    />
  );
}
