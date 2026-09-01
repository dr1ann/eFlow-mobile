let fallbackSequence = 0;

type RuntimeCrypto = {
  getRandomValues?: (values: Uint8Array) => Uint8Array;
  randomUUID?: () => string;
};

/**
 * Generates an RFC 4122 version-4 UUID for an evidence submission attempt.
 *
 * The identifier is not an authorization credential: database and Storage access are
 * enforced by server-side RLS, RPCs, and Storage policies. Prefer the runtime Web
 * Crypto API when it is available, but keep the workflow usable in an existing Expo
 * development binary that does not contain a newly added native crypto module.
 */
export function createWorkflowUuid(): string {
  const runtimeCrypto = globalThis.crypto as RuntimeCrypto | undefined;

  if (typeof runtimeCrypto?.randomUUID === "function") {
    return runtimeCrypto.randomUUID();
  }

  const bytes = new Uint8Array(16);

  if (typeof runtimeCrypto?.getRandomValues === "function") {
    runtimeCrypto.getRandomValues(bytes);
  } else {
    fillFallbackUuidBytes(bytes);
  }

  return formatUuidV4(bytes);
}

export function formatUuidV4(bytes: Uint8Array): string {
  if (bytes.length !== 16) {
    throw new Error("A UUID requires exactly 16 bytes.");
  }

  const uuidBytes = Uint8Array.from(bytes);
  uuidBytes[6] = (uuidBytes[6]! & 0x0f) | 0x40;
  uuidBytes[8] = (uuidBytes[8]! & 0x3f) | 0x80;

  const hex = Array.from(uuidBytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function fillFallbackUuidBytes(bytes: Uint8Array): void {
  fallbackSequence = (fallbackSequence + 1) >>> 0;
  let state = (Date.now() ^ fallbackSequence ^ Math.floor(performance.now() * 1_000)) >>> 0;

  for (let index = 0; index < bytes.length; index += 1) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    bytes[index] = (state ^ Math.floor(Math.random() * 256)) & 0xff;
  }
}
