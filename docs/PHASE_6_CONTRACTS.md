# Phase 6 — Mobile planning and delegation contract record

## Status

- Recorded: September 17, 2026
- Mobile status: P6.3 Task-Lead subtask-planning UI and guarded adapters are implemented locally. Every Phase 6 write capability defaults off. P6.1 task creation and P6.2 Department Head participant/reviewer assignment are not enabled or claimed as live.
- Upstream checked: `46e6f520c5e4dcd71c4e6ae40610518079b71b7c` on `main`.
- Adopted mobile compatibility baseline remains `508aabc8881630b37a62a973645ecb0bb386e99e`.
- Earlier September 17 source notes in [`docs/sql/phase-5-project-5-test.md`](sql/phase-5-project-5-test.md) record that no migrations changed between the prior inspected revision and this upstream SHA. This record re-audits the current planning sources; it does not treat source inspection as deployment proof.

## Implemented guarded mobile slice

```text
RLS-authorized task detail
  -> effective Task Lead only (assigned_to before recommendation_lead_id)
  -> task-owned, already-visible team participants only
  -> create / reassign / schedule / order / set sequential-versus-standalone mode
  -> invalidate task, work, review, and notification queries
  -> existing execution and Phase 4 evidence-review flow
```

The route is `tasks/[task-id]/plan`. It re-reads the task and subtasks under RLS, applies the effective-Task-Lead UX guard, locks started/submitted/completed subtask structure in the UI, and rejects offline mutations. Each action has its own explicit `EXPO_PUBLIC_PHASE_2_LIVE_CAPABILITIES` value:

| Action | Capability | Mobile write path | Default |
| --- | --- | --- | --- |
| Create manual subtask | `subtaskCreate` | `subtasks` INSERT | Off |
| Reassign untouched subtask | `subtaskAssign` | `subtasks` UPDATE | Off |
| Change due date | `subtaskDeadline` | `set_subtask_due_date` RPC | Off |
| Reorder | `subtaskReorder` | `reorder_task_subtasks` RPC | Off |
| Set sequential/standalone mode | `subtaskExecutionRules` | `subtasks` UPDATE | Off |

These flags are release controls only. RLS, triggers, and RPCs must still deny every forbidden request. The app does not query `profiles` to assemble a department-wide picker; the upstream source still permits every signed-in user to read profiles, so it is not a permission-scoped participant source.

## Current source evidence and gaps

| Surface | Current source evidence | Why it is insufficient for a live Phase 6 claim |
| --- | --- | --- |
| Task creation | `supabase/migrations/20260815000002_atomic_task_creation.sql` defines `create_task_with_details(jsonb)`. | It verifies an active caller and assignee, but does not establish an approved project/milestone/reviewer/team scope, idempotency, or one atomic create-and-delegate result. |
| Task assignment | `20260822000000_fix_task_team_assignment_array_types.sql` defines `assign_task_with_details(...)`. | It checks `can_manage_task`, but source inspection does not prove active, organization-scoped team/reviewer eligibility, stale-write behavior, or deployed audit/notification results. |
| People picker | `supabase/fresh_schema.sql` grants signed-in reads to `profiles`; `organization_memberships` source also lacks a Phase 6 eligibility DTO. | A broad directory is not an approved participant/reviewer selector and must not be copied into mobile. |
| Effective Task Lead | `20260826000002_task_leader_only_subtask_management.sql` defines `can_manage_subtasks` as `coalesce(assigned_to, recommendation_lead_id) = auth.uid()`. | The function/policies must be confirmed deployed and tested with actual assigned, stale-recommended, ordinary-member, inactive, and unrelated identities. |
| Subtask order, schedule, execution mode | `20260819000001_ordered_subtasks.sql`, `20260819000004_subtask_execution_dependencies.sql`, and `20260820000001_hierarchical_deadlines.sql` provide source behavior. | Source does not substitute for allowed/denied deployed probes, and direct structural writes need a confirmed parent-state/stale-write/audit/notification contract before enabling any flag. |

## Required backend handoff before enabling a Phase 6 flag

1. A minimal, permission-scoped participant/reviewer source (prefer an authenticated RPC or view) returning only stable ID, display label, active state, and server-derived eligibility for Task Lead, contributor, primary reviewer, and backup reviewer. It must not expose a broad profile directory.
2. An atomic, idempotent Department Head task-plan operation, or an equivalently documented transaction that creates the task, validates its approved project linkage/schedule, assigns the Task Lead/contributors/reviewers, and records audit/notification effects without leaving an unassigned task after a partial failure.
3. Server checks for same-organization active participants, Task Lead/reviewer collisions, primary/backup uniqueness, valid project and milestone scope, parent/project deadline bounds, dependency cycles, duplicate or stale writes, locked/submitted/completed states, and rollback.
4. A deployment record for each source migration/function/policy and regenerated database types from the agreed non-production project.
5. Sanitized allowed/denied non-production probes for Department Head, Task Lead, contributor, primary/backup reviewer, ordinary member, unrelated user, inactive user, stale recommended lead, Assistant Head, and Super Admin. Record atomic audit/notification outcomes and Android/iOS behavior separately.

## Explicit boundaries

- P6.1/P6.2 remain unavailable; no task-create route or Department Head picker is exposed from mobile.
- P6.3 is a guarded local implementation only, not deployed-contract or device acceptance.
- No client fallback, direct profile enumeration, service-role access, offline replay, or financial workflow is introduced.
- A newly planned subtask can enter the existing execution/review surfaces only after its relevant server capability has passed the required probe and is explicitly enabled.
