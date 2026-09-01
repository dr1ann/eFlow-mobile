import { requireOnlineMutation } from "@/lib/phase-1/online";

describe("online-only mutations", () => {
  it("rejects offline and unknown connectivity without creating a queue", () => {
    expect(() => requireOnlineMutation(false)).toThrow(/not be queued/i);
    expect(() => requireOnlineMutation(undefined)).toThrow(/Reconnect/i);
  });

  it("allows a confirmed online request", () => {
    expect(() => requireOnlineMutation(true)).not.toThrow();
  });
});
