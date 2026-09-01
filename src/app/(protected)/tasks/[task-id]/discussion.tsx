import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { TaskDiscussionScreen } from "@/features/discussions/screens/task-discussion-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function TaskDiscussionRoute() {
  const params = useLocalSearchParams<{ "task-id": string | string[] }>();
  const taskId = parseUuidParam(params["task-id"]);
  if (!taskId) return <AppScreen><StatusNotice tone="danger">This task link is invalid.</StatusNotice></AppScreen>;
  return <TaskDiscussionScreen taskId={taskId} />;
}
