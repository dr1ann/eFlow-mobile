import { fetch } from "expo/fetch";
import * as Linking from "expo-linking";

import {
  parseEvidenceRules,
  type EvidenceRules,
  type NativeEvidenceAsset
} from "@/features/subtasks/evidence";
import { toSupabaseUserError } from "@/lib/supabase/errors";
import { getSupabaseClient } from "@/lib/supabase/client";

export interface StoredEvidenceUpload {
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw new DOMException("The evidence operation was cancelled.", "AbortError");
}

function decodeDataUri(uri: string): ArrayBuffer {
  const commaIndex = uri.indexOf(",");
  if (commaIndex === -1) throw new Error("Invalid data URI format.");
  const metadata = uri.slice(0, commaIndex);
  const rawData = uri.slice(commaIndex + 1);

  if (metadata.includes(";base64")) {
    if (typeof atob === "function") {
      const binary = atob(rawData);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return bytes.buffer;
    }
    const b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    const clean = rawData.replace(/[^A-Za-z0-9+/=]/g, "");
    let p = 0;
    const bytes: number[] = [];
    while (p < clean.length) {
      const enc1 = b64.indexOf(clean.charAt(p++));
      const enc2 = b64.indexOf(clean.charAt(p++));
      const enc3 = b64.indexOf(clean.charAt(p++));
      const enc4 = b64.indexOf(clean.charAt(p++));
      const chr1 = (enc1 << 2) | (enc2 >> 4);
      const chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
      const chr3 = ((enc3 & 3) << 6) | enc4;
      bytes.push(chr1);
      if (enc3 !== 64 && enc3 !== -1) bytes.push(chr2);
      if (enc4 !== 64 && enc4 !== -1) bytes.push(chr3);
    }
    return new Uint8Array(bytes).buffer;
  }

  const decoded = decodeURIComponent(rawData);
  const encoder = new TextEncoder();
  return encoder.encode(decoded).buffer;
}

/** Reads a local Expo URI or Data URI without ever displaying or persisting it. */
export async function readEvidenceUri(
  uri: string,
  signal?: AbortSignal
): Promise<ArrayBuffer> {
  throwIfAborted(signal);
  if (uri.startsWith("data:")) {
    return decodeDataUri(uri);
  }
  const response = await fetch(uri, { signal });
  if (!response.ok) throw new Error("The selected file could not be read from this device.");
  const data = await response.arrayBuffer();
  throwIfAborted(signal);
  return data;
}

export async function getTaskEvidenceRules(): Promise<EvidenceRules> {
  const { data, error } = await getSupabaseClient().rpc("get_task_evidence_rules");
  if (error) throw toSupabaseUserError(error);
  return parseEvidenceRules(data);
}

/** Uploads an unguessable, immutable candidate object. It never overwrites. */
export async function uploadTaskEvidence(
  rules: EvidenceRules,
  asset: NativeEvidenceAsset,
  filePath: string,
  signal?: AbortSignal
): Promise<StoredEvidenceUpload> {
  if (!asset.mimeType || asset.size === null) {
    throw new Error("Evidence type and size must be confirmed before upload.");
  }

  const bytes = await readEvidenceUri(asset.uri, signal);
  if (bytes.byteLength !== asset.size) {
    throw new Error("The selected file changed before it could be uploaded.");
  }
  throwIfAborted(signal);

  const { error } = await getSupabaseClient().storage.from(rules.bucketId).upload(
    filePath,
    bytes,
    { contentType: asset.mimeType, upsert: false }
  );
  if (error) throw toSupabaseUserError(error);

  return {
    fileName: asset.displayName,
    filePath,
    fileSize: asset.size,
    mimeType: asset.mimeType
  };
}

/**
 * Claims a path in the database before removing it. A successful claim is
 * durable; callers may safely retry the Storage remove for that same path.
 */
export async function claimAndRemoveTaskEvidence(
  rules: Pick<EvidenceRules, "bucketId">,
  filePath: string
): Promise<"removed" | "missing"> {
  const { data: claimed, error: claimError } = await getSupabaseClient().rpc(
    "claim_task_evidence_cleanup",
    { p_bucket_id: rules.bucketId, p_object_name: filePath }
  );
  if (claimError) throw toSupabaseUserError(claimError);
  if (!claimed) return "missing";

  const { error: removeError } = await getSupabaseClient().storage
    .from(rules.bucketId)
    .remove([filePath]);
  if (removeError) throw toSupabaseUserError(removeError);
  return "removed";
}

/** Removes only the caller's unfinalized candidate paths, in a safe sequence. */
export async function cleanupTaskEvidence(
  rules: Pick<EvidenceRules, "bucketId">,
  filePaths: readonly string[]
): Promise<void> {
  for (const filePath of filePaths) {
    await claimAndRemoveTaskEvidence(rules, filePath);
  }
}

/** Returns a short-lived URL and deliberately leaves ownership/persistence to the caller. */
export async function createTaskEvidenceSignedUrl(
  rules: Pick<EvidenceRules, "bucketId" | "recommendedSignedUrlSeconds">,
  filePath: string
): Promise<string> {
  const { data, error } = await getSupabaseClient().storage
    .from(rules.bucketId)
    .createSignedUrl(filePath, rules.recommendedSignedUrlSeconds);
  if (error || !data?.signedUrl) throw toSupabaseUserError(error ?? new Error("Missing signed URL."));
  return data.signedUrl;
}

export class EvidenceOpeningError extends Error {
  constructor(
    readonly kind: "cancelled" | "unavailable"
  ) {
    super(
      kind === "cancelled"
        ? "Opening the evidence was cancelled. Try again when you are ready."
        : "We could not open this evidence file. Try again."
    );
    this.name = "EvidenceOpeningError";
  }
}

function isEvidenceOpeningCancellation(error: unknown): boolean {
  return error instanceof Error && (
    error.name === "AbortError" || /\bcancel(?:led|ed)?\b/i.test(error.message)
  );
}

/**
 * Signs and opens private evidence only when the user requests it. The signed
 * URL stays within this call and is never stored in query state or persistence.
 */
export async function openTaskEvidence(filePath: string): Promise<void> {
  try {
    const rules = await getTaskEvidenceRules();
    const signedUrl = await createTaskEvidenceSignedUrl(rules, filePath);
    await Linking.openURL(signedUrl);
  } catch (error) {
    if (error instanceof EvidenceOpeningError) throw error;
    throw new EvidenceOpeningError(
      isEvidenceOpeningCancellation(error) ? "cancelled" : "unavailable"
    );
  }
}
