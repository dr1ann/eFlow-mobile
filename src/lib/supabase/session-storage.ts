import * as SecureStore from "expo-secure-store";

const CHUNK_SIZE = 1_200;
const MAX_CHUNKS = 96;

export interface SecureStoreDriver {
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(key: string, value: string): Promise<void>;
  deleteItemAsync(key: string): Promise<void>;
}

export interface SessionStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

interface SessionMetadata {
  version: 1;
  generation: string;
  chunks: number;
  length: number;
}

function metadataKey(key: string): string {
  return `${key}.metadata`;
}

function chunkKey(key: string, generation: string, index: number): string {
  return `${key}.chunk.${generation}.${index}`;
}

function parseMetadata(raw: string | null): SessionMetadata | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<SessionMetadata>;
    const { version, generation, chunks, length } = value;
    if (
      version !== 1 ||
      typeof generation !== "string" ||
      !generation ||
      !Number.isInteger(chunks) ||
      chunks === undefined ||
      chunks < 1 ||
      chunks > MAX_CHUNKS ||
      !Number.isInteger(length) ||
      length === undefined ||
      length < 0
    ) {
      return null;
    }
    return { version, generation, chunks, length };
  } catch {
    return null;
  }
}

async function removeGeneration(
  driver: SecureStoreDriver,
  key: string,
  metadata: SessionMetadata | null
): Promise<void> {
  if (!metadata) return;
  await Promise.all(
    Array.from({ length: metadata.chunks }, (_, index) =>
      driver.deleteItemAsync(chunkKey(key, metadata.generation, index))
    )
  );
}

function createGeneration(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * A SecureStore-only adapter for Supabase Auth.
 *
 * SecureStore item sizes vary by platform. A serialized Supabase session can
 * exceed one item, so it is split across small SecureStore entries. No token
 * or session data is written to ordinary local storage.
 */
export function createChunkedSessionStorage(
  driver: SecureStoreDriver = SecureStore
): SessionStorage {
  return {
    async getItem(key) {
      const metadataRaw = await driver.getItemAsync(metadataKey(key));
      const metadata = parseMetadata(metadataRaw);

      if (!metadata) {
        if (metadataRaw) await driver.deleteItemAsync(metadataKey(key));
        return null;
      }

      const chunks = await Promise.all(
        Array.from({ length: metadata.chunks }, (_, index) =>
          driver.getItemAsync(chunkKey(key, metadata.generation, index))
        )
      );

      if (chunks.some((chunk) => chunk === null)) {
        await removeGeneration(driver, key, metadata);
        await driver.deleteItemAsync(metadataKey(key));
        return null;
      }

      const value = chunks.join("");
      if (value.length !== metadata.length) {
        await removeGeneration(driver, key, metadata);
        await driver.deleteItemAsync(metadataKey(key));
        return null;
      }

      return value;
    },

    async setItem(key, value) {
      const chunks = Array.from(
        { length: Math.ceil(value.length / CHUNK_SIZE) || 1 },
        (_, index) => value.slice(index * CHUNK_SIZE, (index + 1) * CHUNK_SIZE)
      );

      if (chunks.length > MAX_CHUNKS) {
        throw new Error("The secure authentication session is unexpectedly large.");
      }

      const oldMetadata = parseMetadata(await driver.getItemAsync(metadataKey(key)));
      const generation = createGeneration();

      await Promise.all(
        chunks.map((chunk, index) =>
          driver.setItemAsync(chunkKey(key, generation, index), chunk)
        )
      );

      const metadata: SessionMetadata = {
        version: 1,
        generation,
        chunks: chunks.length,
        length: value.length
      };
      await driver.setItemAsync(metadataKey(key), JSON.stringify(metadata));
      await removeGeneration(driver, key, oldMetadata);
    },

    async removeItem(key) {
      const metadata = parseMetadata(await driver.getItemAsync(metadataKey(key)));
      await driver.deleteItemAsync(metadataKey(key));
      await removeGeneration(driver, key, metadata);
    }
  };
}
