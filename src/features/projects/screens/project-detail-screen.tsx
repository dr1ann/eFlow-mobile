import { useQuery } from "@tanstack/react-query";
import { ActivityIndicator, Text, useColorScheme, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  projectPriorityLabel,
  projectStatusLabel,
  type ProjectOverview
} from "@/contracts/projects";
import { projectDetailQueryOptions } from "@/features/projects/query-options";
import { ProjectLifecyclePanel } from "@/features/projects/screens/project-lifecycle-panel";
import { formatTaskDate } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function ProjectDetailView({
  project,
  lifecycle
}: {
  project: ProjectOverview;
  lifecycle?: React.ReactNode;
}) {
  useColorScheme();

  return (
    <AppScreen testID="project-detail-screen">
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
    </AppScreen>
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
  const query = useQuery(projectDetailQueryOptions(projectId));

  if (query.isLoading) {
    return (
      <AppScreen testID="project-detail-loading">
        <ActivityIndicator accessibilityLabel="Loading project" color={colors.primary} />
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Loading project…
        </Text>
      </AppScreen>
    );
  }

  if (query.isError) {
    return (
      <AppScreen testID="project-detail-error">
        <StatusNotice tone="danger">
          We could not open this project. It may be unavailable, or your access may have changed.
        </StatusNotice>
        <Button label="Try again" onPress={() => void query.refetch()} />
      </AppScreen>
    );
  }

  if (!query.data) {
    return (
      <AppScreen testID="project-detail-unavailable">
        <StatusNotice tone="danger">
          This project is unavailable or you do not have access to it.
        </StatusNotice>
      </AppScreen>
    );
  }

  return <ProjectDetailView project={query.data} lifecycle={<ProjectLifecyclePanel project={query.data} />} />;
}
