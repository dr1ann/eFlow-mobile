import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { SubtaskDetailScreen } from "@/features/subtasks/screens/subtask-detail-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function SubtaskDetailRoute() {
  const params = useLocalSearchParams<{ "subtask-id": string | string[] }>();
  const subtaskId = parseUuidParam(params["subtask-id"]);

  if (!subtaskId) {
    return (
      <AppScreen testID="invalid-subtask-route">
        <StatusNotice tone="danger">This subtask link is invalid.</StatusNotice>
      </AppScreen>
    );
  }

  return <SubtaskDetailScreen subtaskId={subtaskId} />;
}
