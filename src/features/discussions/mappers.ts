import { z } from "zod";

import { ContractMappingError } from "@/contracts/contract-errors";
import type { TaskComment } from "@/contracts/discussions";

const commentRowSchema = z.object({
  id: z.string().uuid(),
  task_id: z.string().uuid(),
  author_id: z.string().uuid().nullable(),
  author_name: z.string(),
  body: z.string(),
  created_at: z.string(),
  edited_at: z.string().nullable(),
  deleted_at: z.string().nullable()
});

export function mapTaskCommentRow(row: unknown): TaskComment {
  const parsed = commentRowSchema.safeParse(row);
  if (!parsed.success) throw new ContractMappingError("task comment");

  const data = parsed.data;
  return {
    id: data.id,
    taskId: data.task_id,
    authorId: data.author_id,
    authorName: data.author_name,
    body: data.body,
    createdAt: data.created_at,
    editedAt: data.edited_at,
    deletedAt: data.deleted_at
  };
}
