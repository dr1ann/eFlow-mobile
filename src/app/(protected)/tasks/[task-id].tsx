import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { TaskDetailScreen } from "@/features/tasks/screens/task-detail-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function TaskDetailRoute() {
  const params = useLocalSearchParams<{ "task-id": string | string[] }>();
  const taskId = parseUuidParam(params["task-id"]);

  if (!taskId) {
    return (
      <AppScreen testID="invalid-task-route">
        <StatusNotice tone="danger">This task link is invalid.</StatusNotice>
      </AppScreen>
    );
  }

  return <TaskDetailScreen taskId={taskId} />;
}
