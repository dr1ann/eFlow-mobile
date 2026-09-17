import { useLocalSearchParams } from "expo-router";

import { SubtaskPlanningScreen } from "@/features/subtasks/screens/subtask-planning-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function TaskSubtaskPlanningRoute() {
  const { "task-id": taskIdParam } = useLocalSearchParams<{ "task-id"?: string }>();
  const taskId = parseUuidParam(taskIdParam);

  return taskId ? <SubtaskPlanningScreen taskId={taskId} /> : null;
}
