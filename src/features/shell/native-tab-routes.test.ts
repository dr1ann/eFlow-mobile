import { getNativeBottomTabRoutes } from "./native-tab-routes";

describe("getNativeBottomTabRoutes", () => {
  it.each([
    { canOpenProjects: false, canOpenTasks: false },
    { canOpenProjects: false, canOpenTasks: true },
    { canOpenProjects: true, canOpenTasks: false },
    { canOpenProjects: true, canOpenTasks: true }
  ])("keeps every permission combination within the native five-tab limit", (access) => {
    const routes = getNativeBottomTabRoutes(access);

    expect(routes).toContain("more");
    expect(routes).toHaveLength(access.canOpenProjects && access.canOpenTasks ? 5 : access.canOpenProjects || access.canOpenTasks ? 4 : 3);
    expect(routes.length).toBeLessThanOrEqual(5);
  });

  it("keeps secondary destinations out of the native tab bar", () => {
    const routes = getNativeBottomTabRoutes({ canOpenProjects: true, canOpenTasks: true });

    expect(routes).not.toContain("reviews");
    expect(routes).not.toContain("announcements");
    expect(routes).not.toContain("settings");
  });
});
