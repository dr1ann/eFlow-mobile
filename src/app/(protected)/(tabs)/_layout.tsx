import { NativeTabs } from "expo-router/unstable-native-tabs";

import { useAuth } from "@/features/auth/auth-context";
import { getNativeBottomTabRoutes } from "@/features/shell/native-tab-routes";

export default function TabLayout() {
  const { can } = useAuth();
  const routes = getNativeBottomTabRoutes({
    canOpenProjects: can("navigation.projects"),
    canOpenTasks: can("navigation.tasks")
  });

  return (
    <NativeTabs>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Icon sf="house.fill" md="home" />
        <NativeTabs.Trigger.Label>Home</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="notifications">
        <NativeTabs.Trigger.Icon sf="bell.fill" md="notifications" />
        <NativeTabs.Trigger.Label>Inbox</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      {routes.includes("work") ? (
        <NativeTabs.Trigger name="work">
          <NativeTabs.Trigger.Icon sf="checklist" md="checklist" />
          <NativeTabs.Trigger.Label>Work</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ) : null}
      {routes.includes("projects") ? (
        <NativeTabs.Trigger name="projects">
          <NativeTabs.Trigger.Icon sf="folder.fill" md="folder" />
          <NativeTabs.Trigger.Label>Projects</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ) : null}
      <NativeTabs.Trigger name="more">
        <NativeTabs.Trigger.Icon sf="ellipsis.circle.fill" md="more_horiz" />
        <NativeTabs.Trigger.Label>More</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
