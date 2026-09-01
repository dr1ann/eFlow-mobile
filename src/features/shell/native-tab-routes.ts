export type NativeBottomTabName = "index" | "notifications" | "work" | "projects" | "more";

export interface NativeBottomTabAccess {
  canOpenProjects: boolean;
  canOpenTasks: boolean;
}

/**
 * Android's native bottom navigation permits at most five visible items.
 * Reviews, announcements, and settings are therefore stack destinations under More.
 */
export function getNativeBottomTabRoutes({
  canOpenProjects,
  canOpenTasks
}: NativeBottomTabAccess): readonly NativeBottomTabName[] {
  return [
    "index",
    "notifications",
    ...(canOpenTasks ? (["work"] as const) : []),
    ...(canOpenProjects ? (["projects"] as const) : []),
    "more"
  ];
}
