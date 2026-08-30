# Phase 2 contract record

## Status

- Status: P2.1 project domain foundation and the P2.3 project portfolio/detail read slice are implemented locally; Phase 2 is not complete.
- Recorded: August 30, 2026
- Mobile repository baseline: `d9be92fc16287b5c5bf18258c38ca169f1200d50`
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected: `7b072123a20876940be84217dbb6af3ad8d2700f` (not adopted as the mobile baseline)
- Source evidence: generated `src/contracts/database.types.ts`, the supplied 61-file migration archive, and the upstream comparison

The mobile project now offers the following real, read-only journey:

```text
Authorized user with navigation.projects
  -> Projects tab
  -> paginated, searchable, status-filtered RLS-backed project summaries
  -> validated project detail route
  -> RLS-backed project summary or a non-enumerating unavailable state
```

This is a contract-first read slice. It does not prove the selected non-production project's project RLS or Realtime publication, and it does not enable any project, task, review, report, or AI mutation.

## Implemented mobile read contract

| Area | Implemented behavior | Security boundary |
| --- | --- | --- |
| Navigation | The Projects tab and project detail stack route require `navigation.projects`. | The effective permission only controls UI; project table RLS decides every read. |
| Project list | `projects` read with a fixed minimal select, stable `updated_at`/`id` ordering, 25-row pages, title search, and canonical status filters. | The client does not add a presumed organization filter; deployed RLS defines the visible project scope. |
| Project detail | Direct project-ID read maps `null` to one unavailable state. | A route parameter is never proof of access; an RLS-hidden and missing project are intentionally indistinguishable in the UI. |
| Cache | Query keys contain authenticated user ID, status filter, and an opaque search fingerprint rather than a raw project title. Auth sign-out already clears the QueryClient. | Query keys are not authorization or durable storage. |
| Data mapping | Project statuses map to `planning`, `active`, `on_hold`, `completed`, or `archived`; the known legacy read value `in_progress` maps to `active`. Unknown status/priority/identity data fails closed. | The mapper does not authorize or repair invalid backend rows. |

The exact list/detail select is:

```text
id, title, description, status, priority, start_date, target_date,
program_title, owner_id, org_id, archived_at, updated_at
```

No evidence paths, manager notes, personnel profile data, report contents, recommendation reasoning, financial fields, or private AI context are queried or rendered in this slice.

## Verified source surfaces; deployment still authoritative

| Capability | Source reference | Remaining deployment evidence |
| --- | --- | --- |
| Projects | `projects` generated row has canonical status, priority, schedule, owner, organization, program, archive, and timestamps. | Allowed and denied list/detail probes for Department Head, project member, unrelated employee, inactive account, Assistant Head, and Super Admin. |
| Project membership | `project_members(project_id, user_id, role)` exists. | Current write policy appears potentially broader than manager-only behavior; do not enable membership mutation until a restricted atomic contract and denied probes exist. |
| Milestones | `milestones(project_id, title, due_date, sort_order, status, ...)` exists. | Read RLS, publication, and manager-only mutation behavior need allowed/denied probes; no mobile milestone UI is enabled. |
| Task association | `tasks.linked_project_id` and `tasks.milestone_id` are canonical UUID links; legacy `project_id`/`project_title` exist for compatibility. | Verify scope and referential rules before task creation/assignment uses either project relation. |
| Project create | `create_project_with_details(p_payload jsonb)` exists in the migration archive. | Participant organization scope, required audit/notification behavior, rollback, and deployed RLS/RPC probes remain open. |
| Project edit | Current web behavior uses direct writes plus separate audit calls. | An atomic authorized update contract with stale-state handling, audit, required notification, and rollback must be deployed before mobile editing. |

## Explicitly unavailable actions

The following remain disabled or unimplemented until the stated server contract is verified. The mobile client must not bypass these conditions.

| Action | Required before implementation |
| --- | --- |
| Create project | Hardened and identity-tested `create_project_with_details` behavior, including organization-scoped owner/member validation and transaction side effects. |
| Edit project | Approved atomic project-field update RPC. |
| Change members or milestones | Separate approved atomic manager-only contracts and RLS probes. |
| Archive or permanently delete project | Approved lifecycle and destructive-action contract; out of the current mobile slice. |
| Create/assign/schedule tasks | Hardened atomic task create/assign contracts, task deadline RPC, and identity-based RLS/RPC probes. |
| Department workload, attention, and reports | Approved minimal aggregate/view/RPC DTOs, metric definitions, pagination, and privacy probes. |
| Realtime project refresh | Verified publication and RLS event behavior, including duplicate/reconnect/cleanup tests. |
| AI staffing recommendation | Typed queued gateway operation with server-owned context, model allowlist, role authorization, limits, audit, owner-scoped jobs, and explicit human confirmation. |

## Role and permission decisions still open

- Department Head is the intended Phase 2 management actor. The `navigation.projects` permission makes the read UI available only where the effective-permission source allows it.
- Assistant Head operational scope is not approved for mobile. It must remain an explicit backend/product decision rather than an inferred alias.
- Super Admin project and task operational mutations are not allowed by the Phase 2 plan. The current client-wide Super Admin permission shortcut must be reconciled with deployed trigger/policy behavior before any mutation route is introduced.
- Project membership is not a grant to change project membership, milestones, or other management data.

## Required non-production probes

Before treating this read slice as accepted, record results for:

1. Department Head list and direct-detail read within authorized scope.
2. Department Head direct-detail read outside authorized scope.
3. Project member read behavior, if membership is intended to grant visibility.
4. Unrelated employee, inactive/missing-profile, and malformed-role denial.
5. Assistant Head behavior matching the recorded product decision.
6. Super Admin oversight read behavior and explicit operational mutation denial.
7. Project/milestone Realtime publication, duplicate event, reconnect, and cleanup behavior.

Run these only against the designated non-production project with dedicated identities. Do not repair the empty linked migration history, push migrations, or use a service-role key from the mobile repository.
