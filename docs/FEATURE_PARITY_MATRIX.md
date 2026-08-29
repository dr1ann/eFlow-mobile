# Mobile feature parity matrix

| Journey | Phase | Web status | Authoritative contract | Mobile status | Evidence / notes |
| --- | --- | --- | --- | --- | --- |
| Sign in and session restore | 0 | Live | Supabase Auth + `profiles` | In progress | Native secure-session layer and auth shell |
| Active profile and role resolution | 0 | Live | `profiles`, `role_permissions`, `user_permission_overrides` | In progress | Deny inactive/missing/unknown mobile roles |
| Protected navigation | 0 | Live behavior | Expo Router client guard + Supabase RLS | In progress | Deep-link guards are UX; server remains authoritative |
| Authenticated Supabase query | 0 | Live | `profiles` under RLS | In progress | Shell profile query |
| Gateway health | 0 | Live | `system_config.ai_endpoint`, gateway health endpoint | In progress | Typed client with safe endpoint refresh |
| Foreground Realtime | 0 | Live | Supabase publication | In progress | Profiles, permission and config helpers |
| My Tasks, My Subtasks, and leading work | 1 | Live / contract-dependent | Generated `tasks`/`subtasks`, effective Task Lead precedence, assignment and RLS contracts | Partial test slice | Permission-gated, virtualized My Tasks plus guarded task/subtask details are implemented. My Subtasks, leading work, deadlines, and allowed/denied deployed acceptance remain open. |
| Progress, private evidence, and subtask submission | 1 | Live / contract-dependent | Generated progress/submission RPCs and private Storage contract | Local preview only | Assigned contributors can test native document/image selection and normalized metadata. Nothing is uploaded or persisted; mutations and cleanup stay disabled until task-scoped Storage policy is verified. |
| Subtask and parent task review lifecycle | 1 | Live / contract-dependent | Generated versioned submissions, reviewer routing, decision RPCs, RLS | Foundation in progress | Self-review and subtask-readiness selectors are covered; live RLS/RPC probes remain required. |
| Notifications, announcements, and task discussion | 1 | Live / contract-dependent | Generated recipient tables, task comments, RLS, Realtime | Foundation in progress | In-app/foreground only; recipient and participant policies remain unverified. |
| Deadlines, history, and related project overview | 1 | Live / contract-dependent | Generated task/subtask history and read-only project contracts | Partial | Basic task/subtask deadline fields render in detail views. Dedicated deadlines, history, related-project screens, and authorized device reads remain open. |
| AI recommendations | 2 | Contract-dependent | Authenticated FastAPI queued job endpoints | Deferred | No direct AI/Ollama calls from mobile |
