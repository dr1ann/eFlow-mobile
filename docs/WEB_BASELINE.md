# Web baseline audit

- Audited upstream repository: `Rivaly-Kun/eFlow-e-Governance-Project`
- Recorded and current `main` SHA: `0ecffafffc1fc06b5c12b66014301e78aa659cde`
- Compared: August 25, 2026
- Result: no drift; upstream `main` equals the recorded audit baseline.

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

