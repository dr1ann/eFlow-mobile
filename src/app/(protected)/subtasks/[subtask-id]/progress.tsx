import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { SubtaskProgressScreen } from "@/features/subtasks/screens/subtask-progress-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function SubtaskProgressRoute() {
  const params = useLocalSearchParams<{ "subtask-id": string | string[] }>();
  const subtaskId = parseUuidParam(params["subtask-id"]);
  if (!subtaskId) {
    return <AppScreen><StatusNotice tone="danger">This subtask link is invalid.</StatusNotice></AppScreen>;
  }
  return <SubtaskProgressScreen subtaskId={subtaskId} />;
}
