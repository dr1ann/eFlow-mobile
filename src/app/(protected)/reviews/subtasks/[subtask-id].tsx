import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { SubtaskReviewScreen } from "@/features/reviews/screens/subtask-review-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function SubtaskReviewRoute() {
  const params = useLocalSearchParams<{ "subtask-id": string | string[] }>();
  const subtaskId = parseUuidParam(params["subtask-id"]);
  if (!subtaskId) return <AppScreen><StatusNotice tone="danger">This subtask review link is invalid.</StatusNotice></AppScreen>;
  return <SubtaskReviewScreen subtaskId={subtaskId} />;
}
