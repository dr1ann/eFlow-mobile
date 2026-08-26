import { z } from "zod";

export const gatewayHealthSchema = z.object({
  status: z.literal("ok"),
  service: z.string().min(1)
});

export type GatewayHealth = z.infer<typeof gatewayHealthSchema>;

