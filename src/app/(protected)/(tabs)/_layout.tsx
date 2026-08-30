import { NativeTabs } from "expo-router/unstable-native-tabs";

import { useAuth } from "@/features/auth/auth-context";

export default function TabLayout() {
  const { can } = useAuth();

  return (
    <NativeTabs>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Icon sf="house.fill" md="home" />
        <NativeTabs.Trigger.Label>Home</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      {can("navigation.tasks") ? (
        <NativeTabs.Trigger name="work">
          <NativeTabs.Trigger.Icon sf="checklist" md="checklist" />
          <NativeTabs.Trigger.Label>Work</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ) : null}
      {can("navigation.projects") ? (
        <NativeTabs.Trigger name="projects">
          <NativeTabs.Trigger.Icon sf="folder.fill" md="folder" />
          <NativeTabs.Trigger.Label>Projects</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ) : null}
      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Icon sf="gearshape.fill" md="settings" />
        <NativeTabs.Trigger.Label>Settings</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
