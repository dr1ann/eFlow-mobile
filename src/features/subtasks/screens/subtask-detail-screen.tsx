import { useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { ActivityIndicator, Pressable, ScrollView, Text, useColorScheme, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { subtaskStatusLabel, type Subtask } from "@/contracts/subtasks";
import { useAuth } from "@/features/auth/auth-context";
import { EvidencePickerPreview } from "@/features/subtasks/components/evidence-picker-preview";
import { subtaskDetailQueryOptions } from "@/features/subtasks/query-options";
import { isMySubtask } from "@/features/tasks/selectors";
import { formatTaskDate } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

interface SubtaskDetailViewProps {
  subtask: Subtask;
  canPrepareEvidence: boolean;
  onOpenTask(): void;
}

export function SubtaskDetailView({
  subtask,
  canPrepareEvidence,
  onOpenTask
}: SubtaskDetailViewProps) {
  useColorScheme();

  return (
    <ScrollView
      testID="subtask-detail-screen"
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}
    >
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          {subtask.title}
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          {subtaskStatusLabel(subtask.status)} · {subtask.percentComplete}% complete
        </Text>
      </View>

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
          Execution details
        </Text>
        <DetailValue label="Due date" value={formatTaskDate(subtask.dueDate)} />
        <DetailValue label="Reviewer" value={subtask.reviewerId ? "Assigned" : "Not resolved"} />
        <DetailValue label="Submission state" value={subtask.latestSubmissionId ? "Has a submission" : "Not submitted"} />
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Open parent task"
          onPress={onOpenTask}
          style={({ pressed }) => ({
            minHeight: tokens.touchTarget,
            justifyContent: "center",
            opacity: pressed ? 0.7 : 1
          })}
        >
          <Text style={{ color: colors.primary, fontSize: tokens.type.body, fontWeight: "700" }}>
            Open parent task
          </Text>
        </Pressable>
      </View>

      <View style={{ gap: tokens.space.md }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
          Evidence picker test
        </Text>
        {canPrepareEvidence ? (
          <EvidencePickerPreview />
        ) : (
          <StatusNotice>
            Evidence selection is available only to an assigned contributor while this subtask is editable.
          </StatusNotice>
        )}
      </View>
    </ScrollView>
  );
}

function DetailValue({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ gap: tokens.space.xs }}>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
        {label}
      </Text>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body }}>
        {value}
      </Text>
    </View>
  );
}

export function SubtaskDetailScreen({ subtaskId }: { subtaskId: string }) {
  const router = useRouter();
  const { state } = useAuth();
  const query = useQuery(subtaskDetailQueryOptions(subtaskId));

  if (state.kind !== "authorized") return null;

  if (query.isLoading) {
    return (
      <AppScreen testID="subtask-detail-loading">
        <ActivityIndicator accessibilityLabel="Loading subtask" color={colors.primary} />
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          Loading subtask…
        </Text>
      </AppScreen>
    );
  }

  if (query.isError) {
    return (
      <AppScreen testID="subtask-detail-error">
        <StatusNotice tone="danger">
          We could not open this subtask. It may be unavailable, or your access may have changed.
        </StatusNotice>
        <Button label="Try again" onPress={() => void query.refetch()} />
      </AppScreen>
    );
  }

  if (!query.data) {
    return (
      <AppScreen testID="subtask-detail-unavailable">
        <StatusNotice tone="danger">
          This subtask is unavailable or you do not have access to it.
        </StatusNotice>
      </AppScreen>
    );
  }

  const editableStatus =
    query.data.status === "todo" ||
    query.data.status === "in_progress" ||
    query.data.status === "changes_requested";
  const subtask = query.data;

  return (
    <SubtaskDetailView
      subtask={subtask}
      canPrepareEvidence={editableStatus && isMySubtask(subtask, state.profile.id)}
      onOpenTask={() =>
        router.push({ pathname: "/tasks/[task-id]", params: { "task-id": subtask.taskId } })
      }
    />
  );
}
