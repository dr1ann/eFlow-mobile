import {
  activeRealtimeChannelCount,
  clearRealtimeChannels,
  subscribeToPhase1TaskWorkflow
} from "@/lib/supabase/realtime";

const mockRemoveChannel = jest.fn(async () => undefined);
const mockSubscribe = jest.fn(() => ({ id: "channel" }));
const mockOn = jest.fn(() => ({ subscribe: mockSubscribe }));
const mockChannel = jest.fn(() => ({ on: mockOn }));

jest.mock("@/lib/supabase/client", () => ({
  getSupabaseClient: () => ({
    channel: () => mockChannel(),
    removeChannel: () => mockRemoveChannel()
  })
}));

describe("Phase 1 scoped Realtime subscriptions", () => {
  beforeEach(() => {
    clearRealtimeChannels();
    jest.clearAllMocks();
  });

  it("subscribes only to task-scoped workflow tables and cleans every channel", () => {
    const stop = subscribeToPhase1TaskWorkflow("task-id", jest.fn());

    expect(mockOn).toHaveBeenCalledWith("postgres_changes", expect.objectContaining({
      table: "tasks", filter: "id=eq.task-id"
    }), expect.any(Function));
    expect(mockOn).toHaveBeenCalledWith("postgres_changes", expect.objectContaining({
      table: "subtask_progress_updates", filter: "task_id=eq.task-id"
    }), expect.any(Function));
    expect(activeRealtimeChannelCount()).toBe(6);

    stop();
    expect(activeRealtimeChannelCount()).toBe(0);
    expect(mockRemoveChannel).toHaveBeenCalledTimes(6);
  });
});
