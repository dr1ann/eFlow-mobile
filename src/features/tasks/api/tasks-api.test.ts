import {
  leadingTaskOwnershipFilter,
  myTaskOwnershipFilter
} from "@/features/tasks/api/tasks-api";

const userId = "11111111-1111-4111-8111-111111111111";

describe("task ownership query filters", () => {
  it("includes team membership and the unassigned recommendation fallback for My Tasks", () => {
    expect(myTaskOwnershipFilter(userId)).toBe(
      `assigned_to.eq.${userId},team_member_ids.cs.{${userId}},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`
    );
  });

  it("never treats a stale recommendation as leadership after assignment", () => {
    expect(leadingTaskOwnershipFilter(userId)).toBe(
      `assigned_to.eq.${userId},and(assigned_to.is.null,recommendation_lead_id.eq.${userId})`
    );
  });
});
