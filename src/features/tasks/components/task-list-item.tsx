import { Pressable, Text, View } from "react-native";

import { taskStatusLabel, type Task } from "@/contracts/tasks";
import { formatTaskDate } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export function TaskListItem({ task, onPress }: { task: Task; onPress(): void }) {
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
