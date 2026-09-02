import React from "react";
import { useQuery } from "@tanstack/react-query";
import { ActivityIndicator, Text, View } from "react-native";

import { Button } from "@/components/button";
import { FormField } from "@/components/form-field";
import { StatusNotice } from "@/components/status-notice";
import type {
  ProjectCompletionReadiness
} from "@/features/projects/api/project-workflow-api";
import { useAuth } from "@/features/auth/auth-context";
import { projectCompletionReadinessQueryOptions } from "@/features/projects/query-options";
import { useArchiveProjectMutation, useCompleteProjectMutation } from "@/features/projects/use-project-workflow";
import { isPhase2CapabilityEnabled } from "@/lib/phase-2/capabilities";
import {
  canUsePhase2OperationalCapability,
  phase2OperationalUnavailableMessage
} from "@/lib/phase-2/permissions";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";
import type { ProjectOverview } from "@/contracts/projects";

export interface ProjectLifecycleViewProps {
  project: ProjectOverview;
  readiness: ProjectCompletionReadiness | null;
  loading: boolean;
  error: string | null;
  completionNote: string;
  archiveReason: string;
  completing: boolean;
  archiving: boolean;
  mutationError: string | null;
  onCompletionNoteChange(value: string): void;
  onArchiveReasonChange(value: string): void;
  onRefresh(): void;
  onComplete(): void;
  onArchive(): void;
}

export function ProjectLifecycleView({
  project,
  readiness,
  loading,
  error,
  completionNote,
  archiveReason,
  completing,
  archiving,
  mutationError,
  onCompletionNoteChange,
  onArchiveReasonChange,
  onRefresh,
  onComplete,
  onArchive
}: ProjectLifecycleViewProps) {
  if (project.status === "archived") {
    return <StatusNotice tone="success">This project is archived. Restore is available only on the web.</StatusNotice>;
  }

  if (loading) {
    return (
      <View style={{ gap: tokens.space.sm }}>
        <ActivityIndicator accessibilityLabel="Checking project completion readiness" color={colors.primary} />
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Checking project completion readiness…
        </Text>
      </View>
    );
  }

  if (error || !readiness) {
    return (
      <View style={{ gap: tokens.space.md }}>
        <StatusNotice tone="danger">
          {error ?? "Project completion readiness is unavailable. Refresh and try again."}
        </StatusNotice>
        <Button label="Check readiness again" variant="secondary" onPress={onRefresh} />
      </View>
    );
  }

  if (project.status === "completed") {
    return (
      <View style={{ gap: tokens.space.md }}>
        <StatusNotice tone="success">This project is complete and can now be archived.</StatusNotice>
        <FormField
          label="Archive reason (optional)"
          value={archiveReason}
          onChangeText={onArchiveReasonChange}
          maxLength={1_000}
          autoCapitalize="sentences"
        />
        {mutationError ? <StatusNotice tone="danger">{mutationError}</StatusNotice> : null}
        <Button label="Archive project" variant="danger" loading={archiving} disabled={completing} onPress={onArchive} />
      </View>
    );
  }

  return (
    <View style={{ gap: tokens.space.md }}>
      {readiness.canComplete ? (
        <StatusNotice tone="success">All server-calculated closeout requirements are complete.</StatusNotice>
      ) : (
        <View style={{ gap: tokens.space.sm }}>
          <StatusNotice tone="warning">Resolve every closeout requirement before completing this project.</StatusNotice>
          {readiness.blockers.map((blocker, index) => (
            <View
              key={`${blocker.kind}-${index}`}
              style={{
                gap: tokens.space.xs,
                padding: tokens.space.md,
                borderRadius: tokens.radius.md,
                borderCurve: "continuous",
                borderWidth: 1,
                borderColor: colors.separator,
                backgroundColor: colors.surface
              }}
            >
              <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
                {blocker.title}
              </Text>
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
                {blocker.detail}
              </Text>
            </View>
          ))}
        </View>
      )}
      <FormField
        label="Completion note (optional)"
        value={completionNote}
        onChangeText={onCompletionNoteChange}
        maxLength={1_000}
        autoCapitalize="sentences"
      />
      {mutationError ? <StatusNotice tone="danger">{mutationError}</StatusNotice> : null}
      <Button
        label="Mark project complete"
        loading={completing}
        disabled={!readiness.canComplete || archiving}
        onPress={onComplete}
      />
    </View>
  );
}

export function ProjectLifecyclePanel({ project }: { project: ProjectOverview }) {
  const { state } = useAuth();
  const [completionNote, setCompletionNote] = React.useState("");
  const [archiveReason, setArchiveReason] = React.useState("");
  const completeMutation = useCompleteProjectMutation();
  const archiveMutation = useArchiveProjectMutation();
  const profile = state.kind === "authorized" ? state.profile : null;
  const canComplete = profile
    ? canUsePhase2OperationalCapability(
        profile,
        "projects.archive",
        "projectComplete",
        isPhase2CapabilityEnabled
      )
    : false;
  const canArchive = profile
    ? canUsePhase2OperationalCapability(
        profile,
        "projects.archive",
        "projectArchive",
        isPhase2CapabilityEnabled
      )
    : false;
  const enabled = canComplete || canArchive;
  const readinessQuery = useQuery({
    ...projectCompletionReadinessQueryOptions(project.id),
    enabled
  });

  if (!profile) return null;

  if (!enabled) {
    return <StatusNotice tone="warning">{phase2OperationalUnavailableMessage(profile)}</StatusNotice>;
  }

  const complete = (): void => {
    if (!canComplete) return;
    completeMutation.mutate({ projectId: project.id, note: completionNote });
  };
  const archive = (): void => {
    if (!canArchive) return;
    archiveMutation.mutate({ projectId: project.id, reason: archiveReason });
  };
  const mutationError = completeMutation.error ?? archiveMutation.error;

  return (
    <ProjectLifecycleView
      project={project}
      readiness={readinessQuery.data ?? null}
      loading={readinessQuery.isLoading}
      error={readinessQuery.error instanceof Error ? readinessQuery.error.message : null}
      completionNote={completionNote}
      archiveReason={archiveReason}
      completing={completeMutation.isPending}
      archiving={archiveMutation.isPending}
      mutationError={mutationError instanceof Error ? mutationError.message : null}
      onCompletionNoteChange={setCompletionNote}
      onArchiveReasonChange={setArchiveReason}
      onRefresh={() => void readinessQuery.refetch()}
      onComplete={complete}
      onArchive={archive}
    />
  );
}
