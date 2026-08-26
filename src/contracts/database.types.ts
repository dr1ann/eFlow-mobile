/**
 * Phase 0 audited schema projection for the eFlow baseline.
 *
 * Run `npm run supabase:types` with SUPABASE_PROJECT_REF to replace this
 * bootstrap projection with generated types from the deployed project. Once
 * generated, do not extend it with feature-specific tables by hand.
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

type NoRelationships = [];

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string;
          email: string;
          avatar_path: string | null;
          email_notifications_enabled: boolean;
          employee_id: string;
          org_id: string | null;
          role: string;
          skills: Json;
          workload: number;
          burnout_level: "low" | "medium" | "high";
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          full_name?: string;
          email?: string;
          avatar_path?: string | null;
          email_notifications_enabled?: boolean;
          employee_id?: string;
          org_id?: string | null;
          role?: string;
          skills?: Json;
          workload?: number;
          burnout_level?: "low" | "medium" | "high";
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: NoRelationships;
      };
      system_config: {
        Row: { key: string; value: string; updated_at: string };
        Insert: { key: string; value?: string; updated_at?: string };
        Update: { key?: string; value?: string; updated_at?: string };
        Relationships: NoRelationships;
      };
      role_permissions: {
        Row: { role: string; permission: string; allowed: boolean };
        Insert: { role: string; permission: string; allowed?: boolean };
        Update: { role?: string; permission?: string; allowed?: boolean };
        Relationships: NoRelationships;
      };
      user_permission_overrides: {
        Row: {
          user_id: string;
          permission: string;
          allowed: boolean;
          set_by: string | null;
          created_at: string;
          updated_at: string | null;
        };
        Insert: {
          user_id: string;
          permission: string;
          allowed: boolean;
          set_by?: string | null;
          created_at?: string;
          updated_at?: string | null;
        };
        Update: {
          user_id?: string;
          permission?: string;
          allowed?: boolean;
          set_by?: string | null;
          created_at?: string;
          updated_at?: string | null;
        };
        Relationships: NoRelationships;
      };
    };
    Views: Record<string, never>;
    Functions: {
      has_permission: {
        Args: { p_user_id: string; p_permission: string };
        Returns: boolean;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}
