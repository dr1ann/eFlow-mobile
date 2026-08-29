import { useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, FlatList, Pressable, Text, useColorScheme, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { subtaskStatusLabel, type Subtask } from "@/contracts/subtasks";
import { taskStatusLabel, type Task } from "@/contracts/tasks";
import { subtasksByTaskQueryOptions } from "@/features/subtasks/query-options";
import { taskDetailQueryOptions } from "@/features/tasks/query-options";
import { formatTaskDate } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

interface TaskDetailViewProps {
  task: Task;
  subtasks: readonly Subtask[];
  subtasksLoading: boolean;
  subtasksError: boolean;
  onOpenSubtask(subtaskId: string): void;
  onRetrySubtasks(): void;
}

export function TaskDetailView({
  task,
  subtasks,
  subtasksLoading,
  subtasksError,
  onOpenSubtask,
  onRetrySubtasks
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
            <DetailValue label="Project" value={task.projectTitle ?? "No related project"} />
          </DetailSection>

          <StatusNotice tone="warning">
            Evidence upload and submission remain disabled. Opening a subtask allows local picker testing only; no file leaves the device.
          </StatusNotice>

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
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const subtasksQuery = useQuery({
    ...subtasksByTaskQueryOptions(taskId),
    enabled: taskQuery.data !== null && taskQuery.isSuccess
  });

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

  return (
    <TaskDetailView
      task={taskQuery.data}
      subtasks={subtasksQuery.data ?? []}
      subtasksLoading={subtasksQuery.isLoading}
      subtasksError={subtasksQuery.isError}
      onRetrySubtasks={() => void subtasksQuery.refetch()}
      onOpenSubtask={(subtaskId) =>
        router.push({ pathname: "/subtasks/[subtask-id]", params: { "subtask-id": subtaskId } })
      }
    />
  );
}
