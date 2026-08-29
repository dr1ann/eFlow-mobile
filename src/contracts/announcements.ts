export interface Announcement {
  id: string;
  title: string;
  body: string;
  status: "published" | "draft" | "archived" | "unknown";
  audience: string;
  publishedAt: string | null;
  expiresAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AnnouncementRecipient {
  announcementId: string;
  userId: string;
  readAt: string | null;
}
