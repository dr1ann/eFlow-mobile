import { createChunkedSessionStorage, type SecureStoreDriver } from "@/lib/supabase/session-storage";

const secureStoreKeyPattern = /^[A-Za-z0-9._-]+$/;

function createMemoryDriver(): SecureStoreDriver & { values: Map<string, string> } {
  const values = new Map<string, string>();
  const assertValidKey = (key: string): void => {
    if (!key || !secureStoreKeyPattern.test(key)) {
      throw new Error("Invalid key provided to SecureStore.");
    }
  };

  return {
    values,
    getItemAsync: async (key) => {
      assertValidKey(key);
      return values.get(key) ?? null;
    },
    setItemAsync: async (key, value) => {
      assertValidKey(key);
      values.set(key, value);
    },
    deleteItemAsync: async (key) => {
      assertValidKey(key);
      values.delete(key);
    }
  };
}

describe("chunked SecureStore session storage", () => {
  it("round-trips a session larger than one SecureStore entry", async () => {
    const driver = createMemoryDriver();
    const storage = createChunkedSessionStorage(driver);
    const session = "token-".repeat(1_000);

    await storage.setItem("supabase-session", session);

    expect(driver.values.size).toBeGreaterThan(2);
    await expect(storage.getItem("supabase-session")).resolves.toBe(session);
  });

  it("clears a corrupt stored session rather than returning partial credentials", async () => {
    const driver = createMemoryDriver();
    const storage = createChunkedSessionStorage(driver);
    await storage.setItem("supabase-session", "valid-session");

    const chunk = [...driver.values.keys()].find((key) => key.includes("supabase-session.chunk."));
    if (!chunk) throw new Error("Expected a session chunk.");
    driver.values.delete(chunk);

    await expect(storage.getItem("supabase-session")).resolves.toBeNull();
    expect(driver.values.has("supabase-session:metadata")).toBe(false);
  });

  it("removes all reachable session chunks on sign-out", async () => {
    const driver = createMemoryDriver();
    const storage = createChunkedSessionStorage(driver);
    await storage.setItem("supabase-session", "token-".repeat(1_000));
    await storage.removeItem("supabase-session");

    expect([...driver.values.keys()].filter((key) => key.startsWith("supabase-session"))).toHaveLength(0);
  });

  it("uses only physical keys accepted by Expo SecureStore", async () => {
    const driver = createMemoryDriver();
    const storage = createChunkedSessionStorage(driver);

    await storage.setItem("sb-test-project-auth-token", "session");

    expect([...driver.values.keys()]).not.toHaveLength(0);
    expect([...driver.values.keys()].every((key) => secureStoreKeyPattern.test(key))).toBe(true);
    await expect(storage.getItem("sb-test-project-auth-token")).resolves.toBe("session");
  });
});
