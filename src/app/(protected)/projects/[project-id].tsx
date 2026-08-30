import { useLocalSearchParams } from "expo-router";

import { AppScreen } from "@/components/app-screen";
import { StatusNotice } from "@/components/status-notice";
import { ProjectDetailScreen } from "@/features/projects/screens/project-detail-screen";
import { parseUuidParam } from "@/lib/navigation/params";

export default function ProjectDetailRoute() {
  const params = useLocalSearchParams<{ "project-id": string | string[] }>();
  const projectId = parseUuidParam(params["project-id"]);

  if (!projectId) {
    return (
      <AppScreen testID="invalid-project-route">
        <StatusNotice tone="danger">This project link is invalid.</StatusNotice>
      </AppScreen>
    );
  }

  return <ProjectDetailScreen projectId={projectId} />;
}
