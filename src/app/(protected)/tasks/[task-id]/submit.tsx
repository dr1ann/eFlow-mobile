import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { TaskSubmitScreen } from "@/features/tasks/screens/task-submit-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function TaskSubmitRoute() {
  const params = useLocalSearchParams<{ "task-id": string | string[] }>();
  const taskId = parseUuidParam(params["task-id"]);
  if (!taskId) return <AppScreen><StatusNotice tone="danger">This task link is invalid.</StatusNotice></AppScreen>;
  return <TaskSubmitScreen taskId={taskId} />;
}
