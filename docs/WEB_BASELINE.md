# Web baseline audit

- Audited upstream repository: `Rivaly-Kun/eFlow-e-Governance-Project`
- Recorded audited baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected: `042e1a5b240cf667eb3dfa69d263897686de2a04` in `GabrielCahiyang/eFlow-e-Governance-Project`, rechecked September 6, 2026
- Baseline audit completed: August 27, 2026
- Result: the adopted compatibility marker remains `508aabc`. Current upstream is eight commits ahead; source impact is described in [capstone flow readiness](CAPSTONE_FLOW_READINESS.md). Deployed-policy and device acceptance remain open, so this inspection does not advance the adopted baseline.

## Observed Phase 1 impact

The prior [`0ecffaf..ddca4ae`](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/compare/0ecffafffc1fc06b5c12b66014301e78aa659cde...ddca4ae45ba9fe8e897a9570b2e7b93e8c986cb9) review and the current [`ddca4ae..508aabc`](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/compare/ddca4ae45ba9fe8e897a9570b2e7b93e8c986cb9...508aabc8881630b37a62a973645ecb0bb386e99e) review found:

- Parent task submission now has an explicit client preflight requiring every subtask to be approved. The existing database trigger remains the authorization and lifecycle boundary.
- `20260826000002_task_leader_only_subtask_management.sql` makes the effective Task Lead—`assigned_to`, then `recommendation_lead_id` only when unassigned—the sole manager of subtask structure. Mobile now maps and tests that same precedence.
- The other three new migrations implement contextual task/subtask funding, correction/resubmission, financial attachments, and reviewer notifications. Financial workflows remain deferred beyond the capstone sequence, with no assigned implementation phase.
- Notification navigation recognizes petty-cash review destinations. Phase 1 continues to preserve unknown notification kinds safely without exposing Phase 3 financial actions.
- The supplied August 27 archive contains 61 migrations. Its prior 57 files are content-identical to the earlier source, and all four new Git blob hashes match GitHub `main`.

Source compatibility is verified. Before Phase 1 workflow screens and mutations are accepted, prove the same behavior against the deployed schema, RLS, RPC, Storage, Realtime, role, and permission contracts with allowed and denied test identities.

The later [`508aabc..7b072123`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/508aabc8881630b37a62a973645ecb0bb386e99e...7b072123a20876940be84217dbb6af3ad8d2700f) inspection found no added Supabase migration files. Most changes are web shell, project workspace, styling, login presentation, and repository cleanup, but Phase 1-adjacent role, task-detail/status, review-inbox, and project-query changes still need classification. Do not replace the recorded baseline until that compatibility review and mobile verification are complete.

The subsequent `7b072123..042e1a5b` update adds task-evidence security, project-completion lifecycle, and cash-release schedule migrations. Mobile already has guarded evidence/cleanup and project-lifecycle adapters. The September 6 source review found missing evidence-review presentation, feedback/history, and other workflow gaps despite this integration code; see the readiness report for classification and remaining verification. Current gateway router source files are unchanged from `508aabc`.

## Phase 0 confirmed contracts

| Area | Confirmed contract |
| --- | --- |
| Authentication | Supabase email/password; the mobile client uses only the public publishable/anon key. |
| Profile | Authenticated clients can read `profiles`; the signed-in profile is selected by `id = auth.uid()`. A profile must exist and `is_active` must be true. |
| Roles | Canonical roles: `super_admin`, `dept_head`, `assistant_head`, and `employee`. `department_head` is a legacy alias for `dept_head`; other legacy web-only roles are not enabled for mobile. |
| Permissions | Read `role_permissions` plus signed-in-user `user_permission_overrides`; server helper `has_permission(uuid, text)` is the authorization boundary. |
| Gateway discovery | Read authenticated `system_config` key `ai_endpoint`. It may be an origin or `/controlpanelEflow/api` endpoint. |
| Gateway health | `GET /controlpanelEflow/api/health` returns `{ "status": "ok", "service": "eflow-control-gateway" }`. Gateway authentication is bearer-token based for protected routes; this health endpoint is currently public. |
| Realtime | `profiles`, `system_config`, `role_permissions`, and `user_permission_overrides` are published to Supabase Realtime. |

The health endpoint's current public behavior is retained for compatibility, but the mobile client sends its valid bearer token so the same call remains valid if the gateway is hardened later.
