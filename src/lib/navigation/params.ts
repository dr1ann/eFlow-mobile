import { z } from "zod";

const uuidSchema = z.string().uuid();

export function parseUuidParam(value: string | string[] | undefined): string | null {
  if (typeof value !== "string") return null;
  const parsed = uuidSchema.safeParse(value);
  return parsed.success ? parsed.data : null;
}
