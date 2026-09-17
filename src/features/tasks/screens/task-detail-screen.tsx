import React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, type Href } from "expo-router";
import { ActivityIndicator, FlatList, Pressable, Text, useColorScheme, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { subtaskStatusLabel, type Subtask } from "@/contracts/subtasks";
import { taskStatusLabel, type Task, type TaskSubmission } from "@/contracts/tasks";
import { SubmissionHistory } from "@/features/reviews/components/submission-history";
import { getCurrentTaskReviewSubmission } from "@/features/reviews/submission-selection";
import { subtasksByTaskQueryOptions } from "@/features/subtasks/query-options";
import {
  taskDetailQueryOptions,
  taskSubmissionsQueryOptions
} from "@/features/tasks/query-options";
import { getTaskReviewEligibility, canRequestReviewDecision } from "@/features/reviews/eligibility";
import { useStartTaskMutation } from "@/features/tasks/use-task-workflow";
import { useAuth } from "@/features/auth/auth-context";
import { formatTaskDate } from "@/features/tasks/presentation";
import { isTaskLead } from "@/features/tasks/selectors";
import { isPhase1CapabilityEnabled } from "@/lib/phase-1/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { subscribeToPhase1TaskWorkflow } from "@/lib/supabase/realtime";
import { invalidateTaskWorkflow } from "@/features/workflow/cache-invalidation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

interface TaskDetailViewProps {
  task: Task;
  subtasks: readonly Subtask[];
  subtasksLoading: boolean;
  subtasksError: boolean;
  submissions?: readonly TaskSubmission[];
  submissionsLoading?: boolean;
  submissionsError?: boolean;
  canStartTask?: boolean;
  canSubmitTask?: boolean;
  canReviewTask?: boolean;
  canOpenDiscussion?: boolean;
  canOpenProject?: boolean;
  startingTask?: boolean;
  startError?: string | null;
  onOpenSubtask(subtaskId: string): void;
  onRetrySubtasks(): void;
  onRetrySubmissions?(): void;
  onStartTask?(): void;
  onSubmitTask?(): void;
  onReviewTask?(): void;
  onOpenDiscussion?(): void;
  onOpenProject?(): void;
}

export function TaskDetailView({
  task,
  subtasks,
  subtasksLoading,
  subtasksError,
  submissions = [],
  submissionsLoading = false,
  submissionsError = false,
  canStartTask = false,
  canSubmitTask = false,
  canReviewTask = false,
  canOpenDiscussion = false,
  canOpenProject = false,
  startingTask = false,
  startError = null,
  onOpenSubtask,
  onRetrySubtasks,
  onRetrySubmissions,
  onStartTask,
  onSubmitTask,
  onReviewTask,
  onOpenDiscussion,
  onOpenProject
}: TaskDetailViewProps) {
  useColorScheme();

  return (
    <FlatList
      testID="task-detail-screen"
      data={subtasks}
      keyExtractor={(subtask) => subtask.id}
      contentInsetAdjustmentBehavior="automatic"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{
        flexGrow: 1,
        padding: tokens.space.lg,
        gap: tokens.space.md
      }}
      ListHeaderComponent={
        <View style={{ gap: tokens.space.lg, paddingBottom: tokens.space.sm }}>
          <View style={{ gap: tokens.space.xs }}>
            <Text
              selectable
              style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}
            >
              {task.title}
            </Text>
            <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
              {taskStatusLabel(task.status)} · {task.percentComplete}% complete
            </Text>
          </View>

          {task.feedback ? <StatusNotice tone="warning">{task.feedback}</StatusNotice> : null}

          {canStartTask && onStartTask ? (
            <Button
              label={task.status === "changes_requested" ? "Resume work" : "Start work"}
              loading={startingTask}
              onPress={onStartTask}
            />
          ) : null}
          {canSubmitTask && onSubmitTask ? <Button label="Submit task for review" onPress={onSubmitTask} /> : null}
          {canReviewTask && onReviewTask ? <Button label="Review task submission" onPress={onReviewTask} /> : null}
          {canOpenDiscussion && onOpenDiscussion ? <Button label="Task discussion" variant="secondary" onPress={onOpenDiscussion} /> : null}
          {startError ? <StatusNotice tone="danger">{startError}</StatusNotice> : null}

          <DetailSection title="Schedule">
            <DetailValue label="Deadline" value={formatTaskDate(task.deadline ?? task.dueDate)} />
            <DetailValue label="Priority" value={task.priority ?? "Not set"} />
            <DetailValue label="Dependencies" value={`${task.dependencyIds.length}`} />
          </DetailSection>

          <DetailSection title="Work requirements">
            <DetailValue label="Description" value={task.description ?? "No description provided."} />
            <DetailValue
              label="Definition of done"
              value={task.definitionOfDone ?? "Not provided."}
            />
            <View style={{ gap: tokens.space.xs }}>
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
                Acceptance criteria
              </Text>
              {task.acceptanceCriteria.length > 0 ? (
                task.acceptanceCriteria.map((criterion, index) => (
                  <Text
                    key={`${criterion}-${index}`}
                    selectable
                    style={{ color: colors.label, fontSize: tokens.type.body, lineHeight: 22 }}
                  >
                    • {criterion}
                  </Text>
                ))
              ) : (
                <Text selectable style={{ color: colors.label, fontSize: tokens.type.body }}>
                  No acceptance criteria provided.
                </Text>
              )}
            </View>
          </DetailSection>

          <DetailSection title="People and project">
            <DetailValue label="Task lead" value={task.assigneeName ?? "Not assigned"} />
            <DetailValue label="Team" value={task.teamName ?? "No team name"} />
            {task.linkedProjectId && canOpenProject && onOpenProject ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Open linked project"
                onPress={onOpenProject}
                style={({ pressed }) => ({
                  minHeight: tokens.touchTarget,
                  justifyContent: "center",
                  opacity: pressed ? 0.7 : 1
                })}
              >
                <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
                  Project
                </Text>
                <Text selectable style={{ color: colors.primary, fontSize: tokens.type.body, fontWeight: "700" }}>
                  {task.projectTitle ?? "Open linked project"}
                </Text>
              </Pressable>
            ) : (
              <DetailValue label="Project" value={task.projectTitle ?? "No related project"} />
            )}
          </DetailSection>

          <StatusNotice tone="warning">
            Evidence remains private. Actions appear only after their individual live-operation checks are enabled; server rules still decide access.
          </StatusNotice>

          <SubmissionHistory
            submissions={submissions}
            isLoading={submissionsLoading}
            isError={submissionsError}
            emptyMessage="No task attempts have been submitted yet."
            onRetry={onRetrySubmissions}
          />

          <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
            Subtasks
          </Text>

          {subtasksLoading ? (
            <View style={{ alignItems: "center", gap: tokens.space.sm }}>
              <ActivityIndicator accessibilityLabel="Loading subtasks" color={colors.primary} />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
                Loading subtasks…
              </Text>
            </View>
          ) : null}

          {subtasksError ? (
            <View style={{ gap: tokens.space.md }}>
              <StatusNotice tone="danger">
                We could not load the subtasks for this task.
              </StatusNotice>
              <Button label="Retry subtasks" onPress={onRetrySubtasks} />
            </View>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <SubtaskListItem subtask={item} onPress={() => onOpenSubtask(item.id)} />
      )}
      ListEmptyComponent={
        !subtasksLoading && !subtasksError ? (
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
            No subtasks are visible for this task.
          </Text>
        ) : null
      }
    />
  );
}

function DetailSection({ title, children }: { title: string; children: React.ReactNode }) {
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

function DetailValue({ label, value }: { label: string; value: string }) {
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

function SubtaskListItem({ subtask, onPress }: { subtask: Subtask; onPress(): void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Open ${subtask.title}. ${subtaskStatusLabel(subtask.status)}. ${subtask.percentComplete}% complete.`}
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
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
        {subtask.title}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {subtaskStatusLabel(subtask.status)} · {subtask.percentComplete}% · {formatTaskDate(subtask.dueDate)}
      </Text>
    </Pressable>
  );
}

export function TaskDetailScreen({ taskId }: { taskId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { state, can } = useAuth();
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const startTaskMutation = useStartTaskMutation();
  const submissionsQuery = useQuery({
    ...taskSubmissionsQueryOptions(taskId, 0),
    enabled: taskQuery.isSuccess && taskQuery.data !== null
  });
  const subtasksQuery = useQuery({
    ...subtasksByTaskQueryOptions(taskId),
    enabled: taskQuery.data !== null && taskQuery.isSuccess
  });
  const realtimeEnabled = isPhase1CapabilityEnabled("phase1Realtime");

  React.useEffect(() => {
    if (!realtimeEnabled || !taskQuery.data) return;
    return subscribeToPhase1TaskWorkflow(taskId, () => {
      void invalidateTaskWorkflow(queryClient, taskId);
    });
  }, [queryClient, realtimeEnabled, taskId, taskQuery.data]);

  if (taskQuery.isLoading) {
    return (
      <AppScreen testID="task-detail-loading">
        <ActivityIndicator accessibilityLabel="Loading task" color={colors.primary} />
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Loading task…
        </Text>
      </AppScreen>
    );
  }

  if (taskQuery.isError) {
    return (
      <AppScreen testID="task-detail-error">
        <StatusNotice tone="danger">
          We could not open this task. It may be unavailable, or your access may have changed.
        </StatusNotice>
        <Button label="Try again" onPress={() => void taskQuery.refetch()} />
      </AppScreen>
    );
  }

  if (!taskQuery.data) {
    return (
      <AppScreen testID="task-detail-unavailable">
        <StatusNotice tone="danger">
          This task is unavailable or you do not have access to it.
        </StatusNotice>
      </AppScreen>
    );
  }

  if (state.kind !== "authorized") return null;
  const canStartTask =
    isPhase1CapabilityEnabled("taskTransition") &&
    isTaskLead(taskQuery.data, state.profile.id) &&
    (taskQuery.data.status === "todo" || taskQuery.data.status === "changes_requested");
  const canSubmitTask =
    isPhase1CapabilityEnabled("taskSubmit") &&
    isPhase1CapabilityEnabled("evidenceUpload") &&
    isPhase1CapabilityEnabled("evidenceRules") &&
    isTaskLead(taskQuery.data, state.profile.id) &&
    taskQuery.data.status === "in_progress" &&
    subtasksQuery.isSuccess &&
    (subtasksQuery.data ?? []).every((subtask) => subtask.status === "completed" && subtask.isCompleted);
  const pendingSubmission = getCurrentTaskReviewSubmission(submissionsQuery.data);
  const canReviewTask =
    isPhase1CapabilityEnabled("taskDecision") &&
    pendingSubmission !== undefined &&
    canRequestReviewDecision(getTaskReviewEligibility(taskQuery.data, pendingSubmission, state.profile.id, state.profile.role));
  const startError = startTaskMutation.error instanceof SupabaseUserError
    ? startTaskMutation.error.message
    : startTaskMutation.error instanceof Error
      ? "We could not start this task. Refresh to confirm its current status."
      : null;
  const linkedProjectId = taskQuery.data.linkedProjectId;

  return (
    <TaskDetailView
      task={taskQuery.data}
      subtasks={subtasksQuery.data ?? []}
      subtasksLoading={subtasksQuery.isLoading}
      subtasksError={subtasksQuery.isError}
      submissions={submissionsQuery.data ?? []}
      submissionsLoading={submissionsQuery.isLoading}
      submissionsError={submissionsQuery.isError}
      canStartTask={canStartTask}
      canSubmitTask={canSubmitTask}
      canReviewTask={canReviewTask}
      canOpenDiscussion={isPhase1CapabilityEnabled("taskComments")}
      canOpenProject={can("navigation.projects") && linkedProjectId !== null}
      startingTask={startTaskMutation.isPending}
      startError={startError}
      onRetrySubtasks={() => void subtasksQuery.refetch()}
      onRetrySubmissions={() => void submissionsQuery.refetch()}
      onStartTask={() => startTaskMutation.mutate(taskId)}
      onSubmitTask={() =>
        router.push({ pathname: "/tasks/[task-id]/submit", params: { "task-id": taskId } })
      }
      onReviewTask={() => router.push(`/reviews/tasks/${taskId}` as Href)}
      onOpenDiscussion={() =>
        router.push({ pathname: "/tasks/[task-id]/discussion", params: { "task-id": taskId } })
      }
      onOpenProject={() =>
        linkedProjectId
          ? router.push({
              pathname: "/projects/[project-id]",
              params: { "project-id": linkedProjectId }
            })
          : undefined
      }
      onOpenSubtask={(subtaskId) =>
        router.push({ pathname: "/subtasks/[subtask-id]", params: { "subtask-id": subtaskId } })
      }
    />
  );
}
