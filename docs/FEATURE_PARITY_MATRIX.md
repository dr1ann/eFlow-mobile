# Mobile feature parity matrix

| Journey | Phase | Web status | Authoritative contract | Mobile status | Evidence / notes |
| --- | --- | --- | --- | --- | --- |
| Sign in and session restore | 0 | Live | Supabase Auth + `profiles` | In progress | Native secure-session layer and auth shell |
| Active profile and role resolution | 0 | Live | `profiles`, `role_permissions`, `user_permission_overrides` | In progress | Deny inactive/missing/unknown mobile roles |
| Protected navigation | 0 | Live behavior | Expo Router client guard + Supabase RLS | In progress | Deep-link guards are UX; server remains authoritative |
| Authenticated Supabase query | 0 | Live | `profiles` under RLS | In progress | Shell profile query |
| Gateway health | 0 | Live | `system_config.ai_endpoint`, gateway health endpoint | In progress | Typed client with safe endpoint refresh |
| Foreground Realtime | 0 | Live | Supabase publication | In progress | Profiles, permission and config helpers |
| Employee work and review slice | 1 | Live / contract-dependent | Tasks, subtasks, submissions, RLS/RPCs | Not started | First feature after Phase 0 |
| AI recommendations | 2 | Contract-dependent | Authenticated FastAPI queued job endpoints | Deferred | No direct AI/Ollama calls from mobile |

