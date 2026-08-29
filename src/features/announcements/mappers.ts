import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import type { Announcement, AnnouncementRecipient } from "@/contracts/announcements";

const nullableText = z.string().nullable();

const announcementRowSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(1),
  body: z.string(),
  status: z.string(),
  audience: z.string(),
  published_at: nullableText,
  expires_at: nullableText,
  created_at: z.string(),
  updated_at: z.string()
});

const recipientRowSchema = z.object({
  announcement_id: z.string().uuid(),
  user_id: z.string().uuid(),
  read_at: nullableText
});

function announcementStatus(value: string): Announcement["status"] {
  if (value === "published" || value === "draft" || value === "archived") return value;
  return "unknown";
}

export function mapAnnouncementRow(row: unknown): Announcement {
  const parsed = announcementRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("announcement");

  const data = parsed.data;
  return {
    id: data.id,
    title: data.title,
    body: data.body,
    status: announcementStatus(data.status),
    audience: data.audience,
    publishedAt: data.published_at,
    expiresAt: data.expires_at,
    createdAt: data.created_at,
    updatedAt: data.updated_at
  };
}

export function mapAnnouncementRecipientRow(row: unknown): AnnouncementRecipient {
  const parsed = recipientRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("announcement recipient");

  return {
    announcementId: parsed.data.announcement_id,
    userId: parsed.data.user_id,
    readAt: parsed.data.read_at
  };
}
