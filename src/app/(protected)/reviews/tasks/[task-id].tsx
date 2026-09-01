import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { TaskReviewScreen } from "@/features/reviews/screens/task-review-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function TaskReviewRoute() {
  const params = useLocalSearchParams<{ "task-id": string | string[] }>();
  const taskId = parseUuidParam(params["task-id"]);
  if (!taskId) return <AppScreen><StatusNotice tone="danger">This task review link is invalid.</StatusNotice></AppScreen>;
  return <TaskReviewScreen taskId={taskId} />;
}
