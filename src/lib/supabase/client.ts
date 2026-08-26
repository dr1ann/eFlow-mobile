import "react-native-url-polyfill/auto";

import { createClient, processLock, type SupabaseClient } from "@supabase/supabase-js";

import type { Database } from "@/contracts/database.types";
import { requireRuntimeConfig } from "@/lib/config/runtime";
import { createChunkedSessionStorage } from "@/lib/supabase/session-storage";

let client: SupabaseClient<Database> | null = null;

export function getSupabaseClient(): SupabaseClient<Database> {
  if (client) return client;

  const config = requireRuntimeConfig();
  client = createClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      auth: {
        storage: createChunkedSessionStorage(),
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
        lock: processLock
      }
    }
  );

  return client;
}

export function resetSupabaseClientForTests(): void {
  client = null;
}

