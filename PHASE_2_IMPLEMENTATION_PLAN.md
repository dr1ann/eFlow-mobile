# Phase 2 Implementation Plan — Department Operations and Projects

## Plan status

- Status: P2.1 project-contract foundation and a P2.3 project portfolio/detail read slice are implemented; Phase 2 is not complete
- Current repository phase: Phase 0 foundation, partial Phase 1 read/local-picker paths, and a guarded Phase 2 project read path; deployed-policy, mutation, report, Realtime, AI, and device acceptance remain open
- Mobile repository baseline inspected: `d9be92fc16287b5c5bf18258c38ca169f1200d50`
- Mobile stack: Expo SDK 57, React Native, TypeScript, Expo Router, Supabase, and TanStack Query
- Source roadmap: `MOBILE_IMPLEMENTATION_PHASES.md`
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected: `7b072123a20876940be84217dbb6af3ad8d2700f` (not yet adopted as the mobile baseline)
- Migration reference inspected: `Migrations-20260827T143023Z-1-001/Migrations/`
- Plan created: August 29, 2026; implementation status updated August 30, 2026

Phase 2 must not be reported complete while the Phase 1 deployed-security and device-acceptance gates remain open. Contract work, read-only screens, pure selectors, and backend hardening may advance in parallel, but integrated Department Head mutations require the same non-production Supabase environment, migration history, RLS, Storage, RPC, and test identities used to finish Phase 1.

The current mobile slice exposes only RLS-backed project summary reads. It has a permission-gated Projects tab, 25-row pagination, status filters, title search, validated deep-link detail routes, canonical read mapping, and loading/empty/offline/error states. It deliberately omits project creation/editing, members, milestones, rollups, activity, Realtime, reports, task management, and AI. See `docs/PHASE_2_CONTRACTS.md` for the exact read projection and backend gates.

The web comparison from `508aabc` through `7b072123` contains Phase 2-adjacent project, role, review, and workspace changes but no newly added Supabase migration in the inspected range. The recorded baseline stays at `508aabc` until those changes are classified, mobile compatibility work is implemented, and the shared backend is verified.

## Outcome

Phase 2 will deliver the smallest complete Department Head workflow that extends the Phase 1 employee-to-reviewer slice:

```text
Department Head signs in
  -> sees a permission-scoped department overview and attention queue
  -> creates a project with initial members and milestones atomically
  -> creates a linked task with deadlines, dependencies, and review routing
  -> assigns an eligible employee or team through the authoritative RPC
  -> supervises workload, milestones, task progress, and review readiness
  -> opens the department review inbox and completes an authorized review
  -> inspects read-only project health and permission-scoped reports
  -> optionally requests an AI staffing recommendation
       -> backend creates a typed queued job and assembles private context
       -> mobile resumes the job after navigation or restart
       -> Department Head reviews and edits the draft
       -> explicit confirmation applies the assignment through the normal RPC
```

Ordinary project, task, assignment, review, and report workflows must remain usable when the gateway or AI host is unavailable. AI output is advisory, auditable, and incapable of mutating a project, task, reviewer, team, or employee assignment by itself.

## Scope and product decisions

1. **Primary actor: Department Head.** Phase 2 targets the persisted `dept_head`/`department_head` role and its effective permissions. The web and database also mention `assistant_head`; enabling that role for mobile management is a product and authorization decision, not an alias to assume silently.
2. **Super Admin remains read-only for operational work.** Later database triggers make Super Admin project and task mutations read-only even though older seed permissions and the current mobile `ALL_PERMISSIONS` shortcut may imply otherwise. Phase 2 must reconcile the effective-permission model and test explicit denies.
3. **Use organizational scope from the server.** Organization subtree membership, project membership, task leadership, reviewer routing, and effective permissions come from RLS/RPCs. A role label or client-side filter never grants access.
4. **Mutations are online-only.** Project creation/editing, membership changes, milestone changes, task creation/assignment, deadline changes, review decisions, and recommendation confirmation are never automatically replayed from an offline queue.
5. **Prefer atomic business operations.** Use `create_project_with_details`, `create_task_with_details`, and `assign_task_with_details` only after their deployed behavior is verified and any missing participant-scope or required side-effect checks are hardened. Do not reproduce the web pattern of a table mutation followed by a separate best-effort audit or notification request.
6. **Project edits need a backend contract.** The migration archive contains an atomic project-create RPC, but current web edits, member changes, and milestone changes use separate client writes. Phase 2 will keep those operations read-only until an atomic, authorized update contract is approved and deployed.
7. **Task deadline changes need a backend contract.** `set_subtask_due_date` exists for managed subtask dates; an equivalent authoritative task-date RPC was not found in the inspected migrations. Do not enable direct task deadline updates without one.
8. **Reports are read-only.** Phase 2 includes permission-scoped lists, filters, task drill-down, and concise operational summaries. PDF/CSV export, scheduled reports, and AI management briefs remain Phase 3.
9. **Workload metrics need definitions.** Define and version each health, workload, overdue, blocked, and attention calculation. Avoid copying web selectors that download broad task, personnel, evidence, or private-note datasets to the client.
10. **Projects use canonical statuses.** The database contract accepts `planning`, `active`, `on_hold`, `completed`, and `archived`; mobile must not persist legacy values such as `in_progress` without an explicit compatibility mapping.
11. **Use the canonical project relationship.** New task-to-project work should use `linked_project_id` and `milestone_id`. Legacy text fields such as `project_id` and `project_title` may be read through a compatibility mapper but must not become a second source of truth.
12. **No destructive project management.** Permanent project deletion, bulk destructive edits, governance administration, and complex desktop planning stay web-first unless the user explicitly changes scope. Archive behavior also requires an approved lifecycle contract.
13. **No Phase 3 import or finance creep.** Proposal/PDF import, budget mutations, receipts, push delivery, general chat, calls, and AI management briefs remain out of scope.
14. **Use native mobile interaction patterns.** Virtualize long boards and lists, keep forms keyboard-safe, expose accessible labels and disabled reasons, and use focused screens instead of copying desktop dashboards, tables, timelines, or Kanban drag-and-drop.

## Dependencies and readiness gate

Phase 2 implementation may begin in contract-first increments, but an integrated Phase 2 release requires every item below:

- [ ] Phase 0 device acceptance is complete for Android and iOS.
- [ ] Phase 1 private evidence Storage policies, workflow RLS/RPCs, Realtime behavior, and employee/reviewer journeys pass against the shared non-production backend.
- [ ] The non-production Supabase project has an auditable migration deployment history corresponding to the schema under test.
- [ ] Active Department Head, employee, reviewer, unrelated-organization employee, inactive-user, Assistant Head, and Super Admin test identities are available.
- [ ] The `508aabc..7b072123` upstream changes are classified and any required mobile compatibility work is complete.
- [ ] Generated database types match the selected non-production project after any Phase 2 migration is deployed.
- [ ] Exact effective permissions for project create/edit, task create/assign, department reports, and AI recommendations are approved.
- [ ] Super Admin mutation denial is consistent across database policy, mobile permission resolution, navigation, and tests.
- [ ] The Assistant Head scope decision is recorded; unsupported or denied states fail closed.
- [ ] Atomic project-update/member/milestone and task-deadline contracts are deployed before those actions are enabled.
- [ ] Permission-scoped workload/report contracts return only the fields needed by mobile and do not expose private notes or evidence paths.
- [ ] A typed queued staffing-recommendation gateway contract is deployed before the AI user interface is enabled.
- [ ] Realtime publication and RLS behavior are verified for every Phase 2 table used as an active-app invalidation signal.

If a dependency is unavailable, implement the nearest honest boundary: typed contracts and tested mappers, controlled read-only UI, or a disabled action with a useful explanation. Do not substitute mock data or weaken a server-side check.

## Upstream and contract assessment

### Upstream drift

| Classification | Observation | Phase 2 response |
| --- | --- | --- |
| Pending compatibility review | Upstream `main` advanced from `508aabc` to `7b072123`; project workspace, project queries, role handling, review inbox, task detail, and application-shell behavior changed. | Keep `508aabc` as the recorded baseline until the diff is fully classified and affected mobile contracts/tests pass. |
| Backend unchanged in inspected range | No newly added Supabase migration was found in `508aabc..7b072123`. | Treat application changes as behavior candidates, not proof that the deployed schema or policy changed. |
| Required compatibility | Current project/task code uses both canonical UUID relationships and legacy display/text fields. | Define one mobile compatibility mapper and write new mutations with `linked_project_id`/`milestone_id`. |
| Required verification | The web project workspace and report surfaces aggregate broad client-side datasets. | Replace with minimal permission-scoped reads or dedicated views/RPCs before mobile parity is claimed. |
| Web-only | Desktop panels, data grids, organization trees, wide timelines, and drag-and-drop task boards. | Reimplement only the approved behavior with native lists, filters, forms, and detail routes. |
| Unfinished/unsafe for mobile | Generic AI job submission remains client-model/prompt driven; web recommendation code assembles sensitive context and logs prompts client-side. | Do not reuse it. Require the typed server-owned queued operation described below. |

### Confirmed source contracts and open questions

The migration archive and generated types are source references; the selected deployed project remains authoritative.

| Capability | Current source contract | Required Phase 2 verification or change |
| --- | --- | --- |
| Project read | `projects`, `project_members`, `milestones`; project visibility through owner, membership, organization scope, and RLS helpers | Verify same-org, subtree, member-only, unrelated-org, inactive, and Super Admin reads; confirm pagination and Realtime publication. |
| Project create | `create_project_with_details(p_payload jsonb)` creates the project, owner membership, initial members, and milestones in one transaction. The inspected function checks that selected people are active but does not visibly require them to share the target organization, and it does not visibly emit an audit/notification event. | Define the required participant scope and side effects, harden the RPC where needed, then verify creator roles, duplicate members, milestone/date validation, source values, authorization, and rollback. |
| Project edit | Current web source performs direct project/member/milestone writes and separate audit calls | Add or approve atomic RPCs for project fields, membership, milestones, version/stale-state checks, audit, and notification before enabling mobile edits. |
| Project write RLS | Existing policies appear broader than the desired manager-only contract for project members and milestones | Tighten or prove allowed/denied policy behavior with integration tests; membership alone must not imply management authority. |
| Task create | `create_task_with_details(p_payload jsonb)` creates a task and accepts org, assignee, team arrays, reviewers, dependencies, and project/milestone fields. The inspected function visibly validates an active assignee but does not fully validate every supplied participant/link or visibly create all required audit/notification side effects. | Harden and verify active/org-scoped participants, reviewer eligibility, self-review prevention, dependency validity/cycles, project/milestone scope, date validation, required side-effect atomicity, and duplicate/idempotent behavior. |
| Task assign | `assign_task_with_details(...)` calls `can_manage_task`, updates team/reviewers, applies assignment, and writes related history/notifications | Verify cross-org and inactive denial, array/name consistency, primary/backup uniqueness, self-review, team-member removal with active subtasks, stale state, and repeated requests. |
| Subtask due date | `set_subtask_due_date(uuid, date, text)` enforces manager/lead authority, parent deadline, locked states, reason rules, audit, and notification | Reuse after deployed allowed/denied tests; keep it in the shared Phase 1/2 task-management boundary. |
| Task due date | No equivalent task deadline RPC was found in the inspected migration archive | Backend owner must provide an authoritative mutation or declare the operation web-only. |
| Department review | Phase 1 task/subtask submission and decision contracts plus record-level reviewer routing | Extend the inbox query to department scale without broadening decision authority; no self-review or role-only approval. |
| Productivity snapshots | `monthly_productivity_snapshots` is RLS-readable by allowed scopes; manual recalculation is restricted to Super Admin | Department Head reads only authorized snapshots. Mobile never invokes the maintenance recalculation function. |
| Operational reports | Current web reports are assembled from projects, tasks, people, subtasks, progress, submissions, history, and evidence metadata | Prefer dedicated minimal views/RPCs; prove permissions, pagination, stable metric definitions, and absence of private fields. |
| Staffing AI | Generic `/ai/jobs` exists; typed collaboration-draft recommendations are not the normal Department Head task-assignment operation and are not the required queued contract | Add a typed, queued Department Head staffing endpoint with server-side context, fixed model policy, bounded lifecycle, audit, and human confirmation. |

## Authorization matrix to approve

The matrix below is a target for integration tests, not a replacement for policy. The backend owner and product owner must resolve the Assistant Head row and any narrower effective permissions.

| Action | Department Head | Assistant Head | Employee / project member | Task Lead | Resolved reviewer | Super Admin |
| --- | --- | --- | --- | --- | --- | --- |
| View scoped overview/projects/reports | Allow within authorized organization scope | Decision required | Own/member/assigned scope only | Own/leading scope only | Reviewable-record scope only | Oversight read only |
| Create scoped project | Allow with `projects.create` and RPC authorization | Decision required | Deny | Deny unless separately authorized by server | Deny | Deny operational mutation |
| Edit members or milestones | Allow only through approved atomic RPC | Decision required | Deny even when a member | Deny unless separately authorized | Deny | Deny operational mutation |
| Create scoped task | Allow with `tasks.create` and RPC authorization | Decision required | Deny | Only if an explicit server permission grants it | Deny | Deny operational mutation |
| Assign team/reviewers | Allow with `tasks.assign` and `can_manage_task` | Decision required | Deny | Allow only for records the server says the lead manages | Deny | Deny operational mutation |
| Review submission | Only when resolved reviewer for that record and not submitter | Same record rule | Deny | Deny self-review | Allow for routed record | Deny operational mutation |
| Request staffing recommendation | Allow with dedicated permission and server role check | Decision required | Deny | Deny unless explicitly approved | Deny | Deny operational mutation |
| Confirm recommendation | Same authorization as manual assignment; normal RPC remains authority | Decision required | Deny | Same record rule as manual assignment | Deny | Deny operational mutation |

Every route loads the authenticated access snapshot first and then performs a fresh RLS-backed record read. Cached data from a previously authorized session is removed on sign-out and must not render after permission revocation.

## Data and metric contracts

### Canonical project model

Create generated-schema-backed domain types rather than exposing database rows directly to UI code. At minimum, define and test:

- Project status: `planning | active | on_hold | completed | archived`.
- Project priority: `low | medium | high`.
- Project member role: canonical deployed values, with unknown values rejected or shown safely.
- Milestone identity, order, due date, completion state, and project ownership.
- Task relationship: canonical `linked_project_id` and optional `milestone_id`; legacy labels are display fallbacks only.
- Read model fields for title, owner, organization, schedule, member count, milestone rollup, task rollup, and last activity.
- Mutation inputs separate from read rows, omitting server-owned IDs, audit fields, computed rollups, recommendation reasoning, and protected fields.

### Metric definitions

Before building the overview, write `docs/PHASE_2_CONTRACTS.md` with approved definitions for:

- Total, active, overdue, due-soon, blocked, pending-assignment, and awaiting-review tasks.
- Project health and milestone health, including exact date boundary and timezone behavior.
- Employee workload, capacity, attention, and burnout-warning presentation.
- Completion percentage and whether unapproved 100% progress counts as complete; it should not by default.
- Review age and escalation thresholds.
- Monthly productivity snapshot date windows and freshness.

Prefer server-computed aggregates when they span many records or sensitive inputs. If a selector is computed on-device, fetch only RLS-approved minimal fields, version the calculation, and test boundary dates, empty data, duplicates, stale data, and timezone behavior.

## Target navigation

Keep no more than four primary tabs. The exact information architecture is a product decision during P2.0; one candidate is Work, Manage, Inbox/Reviews, and Settings. The current Phase 0 diagnostics can move under Settings only after its acceptance workflow is preserved.

Routes remain thin adapters under `src/app/`; feature screens and data logic remain outside the router.

```text
src/app/(protected)/
  (tabs)/
    work/                         Existing Phase 1 employee/lead work
    manage/
      index.tsx                   Department overview and attention queue
      tasks.tsx                   Virtualized scoped task board/list
      projects.tsx                Project list and search
      team.tsx                    Workload and attention list
      reports.tsx                 Permission-scoped read-only summaries
    reviews/                      Shared Phase 1/2 review inbox
    settings/
  projects/
    new.tsx                       Atomic project creation
    [id].tsx                      Project detail
    [id]/edit.tsx                 Enabled only after atomic edit contract
    [id]/members.tsx              Read first; mutation contract gated
    [id]/milestones.tsx           Read first; mutation contract gated
  tasks/
    new.tsx                       Atomic task creation
    [id]/assignment.tsx           Manual assignment/team/reviewer form
    [id]/schedule.tsx             Enabled only for authoritative date RPCs
  recommendations/
    [job-id].tsx                  Queued-job state, draft, and confirmation
```

Do not make each management filter a tab. Use accessible segmented controls, search, filter sheets, and saved in-memory view state. Every list needs stable IDs, pagination, pull-to-refresh, empty/error/offline states, and an explicit stale-data indicator.

## Target module boundaries

Extend the feature-first structure without reorganizing the existing app:

```text
src/
  contracts/
    database.types.ts             Generated only
    projects.ts
    department.ts
    reports.ts
    recommendations.ts
  features/
    department/
      api/
      components/
      hooks/
      screens/
      mappers.ts
      query-options.ts
      selectors.ts
    projects/
      api/
      components/
      hooks/
      screens/
      mappers.ts
      query-options.ts
      selectors.ts
      validators.ts
    task-management/
      api/
      components/
      hooks/
      screens/
      mappers.ts
      query-options.ts
      validators.ts
    reports/
      api/
      components/
      screens/
      mappers.ts
      query-options.ts
      selectors.ts
    recommendations/
      api/
      components/
      hooks/
      persistence.ts
      screens/
      query-options.ts
      state.ts
  lib/
    gateway/                       Existing typed gateway client
    query/                         Existing QueryClient policy
    supabase/                      Existing authenticated client
```

Reuse Phase 1 task, subtask, review, identity, notification, and Realtime contracts. Do not create a parallel task model or another server-state cache.

## Query, mutation, and Realtime strategy

### Query keys

Use serializable, organization- and filter-scoped keys. Candidate shapes:

```text
['department', 'overview', orgId, metricVersion]
['department', 'tasks', orgId, filters, cursor]
['department', 'team', orgId, filters, cursor]
['projects', 'list', orgId, filters, cursor]
['projects', 'detail', projectId]
['projects', 'milestones', projectId]
['projects', 'members', projectId]
['reports', reportKind, orgId, filters, cursor]
['recommendations', 'job', jobId]
```

Never put tokens, names, manager notes, report contents, or sensitive payloads in query keys. Cancel and remove all protected queries at sign-out or access revocation.

### Mutation rules

- Set `networkMode: 'online'` and disable automatic retries for all sensitive mutations.
- Generate an idempotency key for a backend operation only when the server contract supports and enforces it.
- Validate inputs on-device for UX, then display server rejection as authoritative.
- Re-fetch the target record/version before assignment or recommendation confirmation to catch stale state.
- Invalidate the smallest affected keys after success: target detail, relevant list pages, overview rollups, team workload, review inbox, and report summaries.
- Do not show success when the business mutation succeeded but a required atomic audit/notification side effect failed; the backend operation must define that transaction boundary.
- Do not retry an unsafe mutation after a gateway endpoint refresh unless the operation has a verified idempotency contract.

### Realtime

Subscribe only while the relevant protected screen is active. Treat events as invalidation signals unless a safe typed merge is proven. Verify:

- organization/project/task scoping under RLS;
- duplicate event handling and stable record IDs;
- pagination and filter behavior when records enter or leave a result set;
- reconnect refresh after network loss or app resume;
- subscription cleanup on unmount, role change, sign-out, and account rejection;
- no reliance on Realtime for background notifications.

## Work packages

### P2.0 — Phase gate, contract ledger, and product decisions

**Implementation**

- Finish or explicitly track the outstanding Phase 0 and Phase 1 acceptance items.
- Create `docs/PHASE_2_CONTRACTS.md` containing deployed schema/RPC signatures, role and permission decisions, RLS test results, metric definitions, Realtime publications, and backend owners.
- Classify upstream `508aabc..7b072123` and update the recorded baseline only after compatibility verification.
- Resolve Assistant Head management scope, Super Admin read-only semantics, the four-tab information architecture, and which project edits are mobile-appropriate.
- Regenerate `src/contracts/database.types.ts` from the selected non-production project after confirmed schema changes.
- Establish representative fixtures and non-production test identities without storing credentials in the repository.

**Tests and acceptance**

- Role/permission tests cover every alias, unsupported role, inactive profile, explicit deny, and Super Admin privilege-escalation attempt.
- Contract probes record at least one allowed and one denied identity for every sensitive read/RPC.
- Generated types, local migrations, and deployed signatures agree or the mismatch is documented as a blocker.
- No Phase 2 mutation route is reachable before its exact effective permission and server authorization are both available.

### P2.1 — Domain contracts and shared management foundation

**Implementation**

- Expand project, department, report, recommendation, task-management, and pagination domain contracts.
- Correct canonical project status and task-to-project mapping.
- Add validators for dates, member/reviewer uniqueness, dependency selection, organization scope hints, and mutation payloads.
- Add typed error mapping for validation, unauthorized, forbidden, stale/conflict, offline, timeout, rate-limit, and unavailable states.
- Add scoped query keys and reusable list/loading/empty/error/permission-denied states.

**Tests and acceptance**

- Pure tests cover valid, boundary, malformed, duplicate, unknown-enum, legacy-field, and deterministic mapping cases.
- Permission selectors fail closed when data is missing, stale, or unsupported.
- Sensitive server fields are absent from UI domain objects and logs.

### P2.2 — Department overview and virtualized task board

**Implementation**

- Build a permission-scoped overview with approved live metrics and attention categories.
- Build a virtualized task list/board with search, status, priority, assignee, project, milestone, overdue, and review-state filters supported by the backend.
- Reuse Phase 1 task detail, review, notification, and task-lead behavior.
- Show freshness, loading, empty, permission-denied, offline/stale, retry, timeout, and server-error states.
- Add foreground Realtime invalidation and reconnect refresh.

**Tests and acceptance**

- Query mapping tests cover pagination boundaries, deduplication, filters, sort order, minimal selects, and typed errors.
- Metric selector tests cover empty data, deadlines at timezone boundaries, blocked dependencies, unapproved 100% work, and duplicate events.
- Screen tests cover accessible filters, pull-to-refresh, disabled actions, stale indicators, permission loss, and retry.
- A realistically large dataset scrolls smoothly on representative Android and iOS devices.

### P2.3 — Project portfolio and detail read path

**Implementation**

- Add project list/search/filter with stable pagination.
- Add project detail for overview, schedule, owner, members, milestones, task rollup, health, and concise activity/timeline data.
- Load only RLS-approved fields needed by each section; do not fetch evidence paths or private manager context.
- Link project tasks and milestones through canonical UUID relationships while safely displaying legacy records.
- Use Realtime invalidation only after publication/RLS verification.

**Tests and acceptance**

- Project mappers reject or safely represent malformed statuses, missing relations, legacy IDs, invalid dates, and unknown member roles.
- Allowed Department Head/member reads and unrelated/inactive/unauthorized denies pass in non-production integration tests.
- List/detail screens cover loading, empty relations, deleted references, partial rollups, offline stale reads, and authorization changes.
- Timeline rendering remains concise and virtualized rather than copying the desktop timeline.

### P2.4 — Atomic project creation and gated editing

**Implementation**

- Build a keyboard-safe, accessible project-create form for title, description, status, priority, schedule, owner, members, and initial milestones.
- After the participant-scope and required side-effect contract is approved, call `create_project_with_details` through one typed adapter and map the returned project.
- Sanitize and deduplicate member selections; validate date ordering and milestone inputs before submission.
- Navigate to the created project only after the RPC succeeds and invalidate portfolio/overview keys.
- Implement basic project-field editing through an approved atomic RPC with authorization, stale-state handling, audit, required notification, and rollback.
- Add member and milestone mutations only if their separately approved atomic contracts meet the same standard; otherwise keep those sections read-only.
- Keep permanent delete and unapproved archive operations unavailable.

**Tests and acceptance**

- Unit tests assert the exact RPC payload and omit server-owned or protected fields.
- Tests cover empty title, status/priority/date boundaries, duplicate members, owner/member conflicts, malformed milestone data, double-submit prevention, offline denial, authorization failure, and server rollback.
- Non-production tests prove allowed Department Head creation and denied employee, unrelated organization, inactive user, unsupported Assistant Head, and Super Admin mutation behavior.
- Failed creation leaves no orphan project, membership, or milestone rows.

### P2.5 — Task creation, assignment, reviewers, dependencies, and deadlines

**Implementation**

- Harden and verify the atomic task-create contract, then build task creation with optional project/milestone association and a safe pending-assignment state.
- Build assignment/team/reviewer management through `assign_task_with_details`.
- Filter directory candidates for UX using authorized server data; the RPC still revalidates eligibility.
- Prevent obvious self-review, duplicate reviewer, invalid dependency, circular dependency, out-of-scope project/milestone, and deadline errors before submission.
- Reuse `set_subtask_due_date`; add and verify the authoritative task-date RPC required to meet the roadmap's deadline-management scope before Phase 2 sign-off.
- Surface server conflict and stale-state responses without silently overwriting newer work.

**Tests and acceptance**

- API tests assert exact create/assign/date payloads, cache invalidation, retry policy, and error mapping.
- Tests cover unassigned creation, representative assignment, inactive/cross-org participants, self-review, duplicate primary/backup, dependency blocking/cycles, project/milestone mismatch, member removal with active subtasks, duplicate requests, and partial-side-effect rollback.
- Integration tests prove `can_manage_task` and reviewer/assignment triggers for allowed and denied identities.
- Created tasks enter the Phase 1 employee workflow and review lifecycle without a second mobile-only state machine.

### P2.6 — Team supervision and department review inbox

**Implementation**

- Build workload and attention lists from approved metrics or dedicated server aggregates.
- Show leading work, unassigned work, overdue/blocked work, milestone risk, and awaiting-review items without exposing private manager notes.
- Extend the Phase 1 review inbox for department scale while preserving record-level reviewer authorization.
- Provide drill-down to existing task/subtask/project screens; do not add role-only review actions.
- Read authorized monthly productivity snapshots when useful, but never invoke maintenance recalculation from mobile.

**Tests and acceptance**

- Workload and attention selectors are deterministic, versioned, and cover empty, boundary, stale, and malformed input.
- Screen tests cover filters, pagination, permission denial, record deletion, Realtime deduplication, and reconnect refresh.
- Review tests cover primary/backup routing, self-review prevention, stale submission versions, duplicate decisions, and unrelated department denial.
- A user may see an aggregate only if the backend also authorizes every underlying scope represented by it.

### P2.7 — Permission-scoped operational reports

**Implementation**

- Add read-only report lists and filters for the approved project/task/team summaries.
- Prefer dedicated paginated views/RPCs that expose minimal, stable DTOs over downloading many workflow tables.
- Reuse authorized task/project drill-down routes and re-check access at navigation time.
- Show metric version/freshness and clearly distinguish no data from lack of permission.
- Defer PDF/CSV generation, scheduled delivery, and AI-authored briefs.

**Tests and acceptance**

- Query tests cover exact filters, pagination, date/timezone boundaries, empty results, server errors, and forbidden responses.
- Integration tests cover Department Head scope, unrelated department denial, employee denial, Assistant Head decision, and Super Admin read-only oversight.
- Privacy tests prove the report payload omits evidence paths, private notes, protected personnel details, raw AI prompts, and unnecessary financial fields.
- Report summaries match the approved metric definitions and drill-down counts for representative fixtures.

### P2.8 — Typed queued AI staffing recommendations

This package begins with backend work. The existing generic AI job route and collaboration-draft recommendation route do not satisfy the normal Phase 2 staffing contract.

**Required backend contract**

- A narrow versioned operation such as create staffing-recommendation job, get authorized job status/result, and cancel job. Exact endpoint names are owned by the backend contract and must be recorded before mobile implementation.
- Authenticated Supabase bearer token, Department Head role/effective-permission check, organization/task authorization, and owner-scoped job reads.
- Client supplies stable business references and editable public constraints, not a model name, arbitrary prompt, personnel dataset, private notes, or hidden scoring context.
- Server loads current task/team/capacity/private context, applies a model allowlist, size limits, rate/concurrency limits, timeouts, expiry, cancellation, and redacted audit events.
- States include at least `queued`, `running`, `succeeded`, `failed`, `expired`, `cancelled`, and `unavailable`, with a versioned structured result.
- Deterministic fallback is used only if the approved business contract explicitly permits it and labels the result source.
- Job creation has an idempotency contract; status reads are safe; unsafe assignment application is never retried automatically.
- Audit failure cannot be silently swallowed when audit is a required side effect.

**Mobile implementation**

- Resolve the gateway through the existing typed client and send the current bearer token.
- Persist only the job ID, owning user/environment identity, operation type, and safe timestamps; never persist prompts, manager notes, tokens, or private candidate context.
- Resume status after navigation, AppState changes, or restart with bounded backoff and a user-triggered refresh; do not poll continuously for hours.
- Render unavailable, queued, running, failed, expired, cancelled, and succeeded states with accessible recovery actions.
- Present recommendations as an editable draft with reasoning that is safe for the authorized user.
- Before confirmation, refresh the task and eligible candidates, show any stale changes, and apply the human-edited result once through `assign_task_with_details`.

**Tests and acceptance**

- Gateway tests cover bearer header, endpoint resolution/rotation, URL joining, timeout, cancellation, redacted errors, rate limits, and all queued-job states.
- Tests prove the client cannot choose a model, inject arbitrary prompts, send private manager notes, view another user's job, or turn a result into an automatic mutation.
- Persistence tests cover restart/resume, corrupt/partial/expired/oversized values, user/environment mismatch, sign-out cleanup, and terminal-state cleanup.
- Confirmation tests cover stale task state, changed candidate eligibility, human edits, duplicate press, offline denial, server rejection, and single RPC application.
- With the gateway or AI host offline, every non-AI Phase 2 workflow remains usable.

### P2.9 — Integrated hardening and release acceptance

**Implementation**

- Run the full Department Head-to-employee-to-reviewer flow against the shared non-production backend.
- Exercise permission revocation, stale sessions, network changes, app suspension, process restart, Realtime reconnect, and AI outage recovery.
- Audit logs, persisted values, query keys, error messages, screenshots, and analytics for sensitive information.
- Verify accessible labels, focus, dynamic text, contrast, touch targets, keyboard avoidance, safe areas, and virtualized scrolling.
- Update `MOBILE_IMPLEMENTATION_PHASES.md`, contract notes, the audited web baseline, and known concerns only when evidence supports the new state.

**Tests and acceptance**

- Targeted tests pass during development.
- `npm run check` passes after every executable/test/config batch and at final integration.
- `npm run build:verify` passes after route, Expo config, dependency, asset, or native integration changes and at final release acceptance.
- Android and iOS manual checks use realistic data and cover both successful and denied journeys.
- Unfinished or backend-blocked actions remain visibly unavailable and are not counted toward Phase 2 completion.

## Test inventory

Final filenames should follow the existing feature layout. At minimum, plan for these test responsibilities:

| Area | Expected automated coverage |
| --- | --- |
| Roles and permissions | Canonical aliases, Assistant Head decision, unknown/inactive profiles, Department Head scope, Super Admin explicit denies, route/deep-link guards |
| Project contracts | Canonical statuses, priorities, member roles, legacy relation mapping, malformed rows, mutation validation |
| Project APIs | Exact selects/RPC payloads, pagination, errors, allowed/denied mapping, invalidation, atomic failure |
| Project UI | List/detail/create states, form feedback, loading/empty/error/offline, duplicate submit, accessibility |
| Department metrics | Approved definitions, date/timezone boundaries, duplicates, stale/empty data, unapproved progress, deterministic output |
| Task management | Create/assign/date payloads, eligibility, self-review, reviewer uniqueness, dependencies, stale conflicts, online-only behavior |
| Reviews | Primary/backup routing, self-review prevention, submission versions, duplicate/stale decisions, cache invalidation |
| Reports | Minimal fields, filters, pagination, metric agreement, forbidden scope, protected-field omission |
| Realtime | Event mapping, duplicate events, paged/filter merge behavior, reconnect refresh, cleanup |
| AI jobs | Auth headers, endpoint rotation, states, backoff, persistence/recovery, privacy, human confirmation, outage independence |
| Navigation | Protected route bootstrap, permission-gated tabs/actions, direct deep links, deleted records, revoked permissions |

Likely colocated files include `src/contracts/projects.test.ts`, `src/features/projects/mappers.test.ts`, `src/features/projects/validators.test.ts`, `src/features/projects/api/projects-api.test.ts`, `src/features/projects/screens/project-list-screen.test.tsx`, `src/features/department/selectors.test.ts`, `src/features/task-management/api/task-management-api.test.ts`, `src/features/reports/api/reports-api.test.ts`, and `src/features/recommendations/hooks/use-recommendation-job.test.tsx`. Use the actual established filenames when implementation begins; do not create placeholder tests.

Non-production integration coverage must include at least:

- Department Head allowed within scope and denied outside scope.
- Employee/project member unable to escalate from read membership to project management.
- Task Lead allowed only for server-authorized records.
- Resolved reviewer allowed only for routed submissions and unable to self-review.
- Assistant Head behavior matching the recorded product decision.
- Super Admin allowed oversight reads and denied operational mutations.
- Inactive, missing-profile, malformed-role, stale-session, and unrelated-organization identities denied.
- Transaction rollback for failed project/task creation and required side effects.
- Report and Realtime results respecting the same RLS boundary as direct reads.

Automated tests must use mocks or the designated non-production environment, never production Supabase, Storage, gateway, or AI services.

## Manual Android and iOS checklist

- [ ] Cold sign-in/session restore reaches the correct permission-gated navigation.
- [ ] Direct links to forbidden, deleted, archived, and unrelated project/task/recommendation records fail safely.
- [ ] Large task, project, team, report, and review lists scroll smoothly with stable positions.
- [ ] Search/filter sheets, date inputs, member/reviewer pickers, and forms work with keyboard, back navigation, and enlarged text.
- [ ] Project and task creation prevent double submission and preserve recoverable draft input after ordinary validation errors.
- [ ] Airplane mode shows stale safe reads where supported and blocks every sensitive mutation.
- [ ] Network reconnect refreshes active data without duplicate records or subscriptions.
- [ ] Background/resume refreshes stale department data and resumes a safe AI status check.
- [ ] Process restart resumes only authorized in-progress AI job IDs and clears invalid/cross-account state.
- [ ] Permission revocation/sign-out removes protected cached data and subscriptions.
- [ ] AI outage is clearly isolated; manual creation, assignment, review, project, and report workflows still function.
- [ ] Light/dark mode, contrast, safe areas, orientation assumptions, touch targets, and screen-reader labels are acceptable.

## Implementation sequence

Implement in this order to preserve vertical value and avoid building UI on unsafe contracts:

1. P2.0 — Phase gate, deployed contract ledger, upstream classification, and product decisions.
2. P2.1 — Domain contracts, generated types, permission corrections, validators, query keys, and error mapping.
3. P2.2 — Read-only Department Head overview and virtualized scoped task board.
4. P2.3 — Read-only project portfolio and detail workflow.
5. P2.4 — Atomic project creation and basic project-field editing; keep member/milestone mutation actions gated until their backend contracts exist.
6. P2.5 — Atomic task creation and assignment; enable only authoritative deadline operations.
7. P2.6 — Team workload, attention, leading work, and scaled review inbox.
8. P2.7 — Permission-scoped reports and drill-down.
9. P2.8 — Typed queued AI recommendation backend, then mobile job and confirmation UI.
10. P2.9 — Integrated security, lifecycle, performance, device, and documentation acceptance.

Each work package should leave the app truthful and releasable at its current boundary. A read-only project view is acceptable before project mutation; a visually complete edit form backed by direct insecure writes is not.

## Phase 2 exit checklist

Phase 2 is complete only when all applicable items are true:

- [ ] Phase 0 and Phase 1 release gates required by this workflow are complete.
- [ ] Department Head can view accurate scoped overview, task, team, project, review, and report data.
- [ ] Department Head can create a project atomically with initial authorized members and milestones.
- [ ] Basic project-field edits use an atomic server contract with authorization, audit, required notification, stale-state handling, and rollback.
- [ ] Department Head can create, assign, schedule, and supervise work through the same authoritative contracts used by web.
- [ ] Created/assigned work completes the Phase 1 evidence, submission, and review lifecycle.
- [ ] Department review actions remain record-routed and prevent self-review and unauthorized deep links.
- [ ] Workload, attention, health, and report metrics use approved definitions and minimal permission-scoped data.
- [ ] Super Admin, Assistant Head, project-member, Task Lead, reviewer, employee, inactive, and unrelated-organization behavior matches the approved authorization matrix.
- [ ] Realtime subscriptions invalidate safely, deduplicate, reconnect, and clean up.
- [ ] All sensitive mutations are online-only and are never replayed automatically.
- [ ] AI staffing requests use a typed queued endpoint; model selection and private context are server-controlled.
- [ ] AI job IDs survive navigation/restart safely, polling is bounded, and sign-out removes persisted state.
- [ ] AI output is an editable draft and cannot mutate assignments without explicit authorized confirmation through the normal RPC.
- [ ] Gateway or AI outage does not block normal Department Head work.
- [ ] Targeted tests, `npm run check`, and applicable `npm run build:verify` commands pass.
- [ ] Android and iOS manual acceptance passes or every platform limitation is documented.
- [ ] `MOBILE_IMPLEMENTATION_PHASES.md`, contract notes, and the audited upstream baseline reflect verified reality.

## Primary risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Phase 1 security debt is hidden by Phase 2 screens | Keep the explicit release gate and reuse the same deployed contracts/test identities; do not count mock or local-only behavior. |
| Broad project-member/milestone RLS permits unauthorized writes | Add denied integration tests and require atomic manager-only RPCs before enabling edits. |
| Mobile permission shortcut gives Super Admin operational powers | Remove the unconditional client grant for affected actions, represent server-effective denies, and test deep links plus RPC rejection. |
| Assistant Head scope is inferred from web labels | Record a product/backend decision and fail closed until permission and RLS behavior agree. |
| Client-derived reports overfetch sensitive data | Introduce minimal paginated server views/RPCs and test protected-field omission. |
| Workload scores drift between web and mobile | Version definitions in the contract ledger and share pure logic only after authoritative inputs are agreed. |
| Task/project creation has partial audit or notification side effects | Require one transactional business operation and failure-atomicity integration tests. |
| Legacy and canonical project fields disagree | Write canonical UUID relationships, map legacy fields for display only, and test conflicts explicitly. |
| Realtime corrupts filtered/paged lists | Use invalidation-first behavior, stable IDs, deduplication, reconnect refresh, and cleanup tests. |
| Generic AI endpoint exposes models, prompts, or private notes | Do not call it for Phase 2; require a typed server-owned operation with allowlists, limits, authorization, and redacted audit. |
| AI result applies stale or unauthorized staffing changes | Re-fetch current records/candidates and use the normal assignment RPC only after explicit human confirmation. |
| Quick Tunnel rotates or AI host is unavailable | Refresh the published endpoint only for safe requests, show useful unavailable states, persist bounded job recovery, and keep ordinary work independent. |
| Scope expands into desktop administration or Phase 3 | Enforce this plan's boundaries and require an explicit product decision before adding destructive administration, exports, import, finance, push, chat, or calls. |

## Documentation verification for this plan

This file is documentation-only, so unit tests are not applicable. Verify it by checking the roadmap, repository state, migration archive, generated database types, upstream comparison, referenced filenames, role names, RPC signatures, phase boundaries, and Markdown structure. Executable tests become mandatory when a work package changes source, tests, dependencies, routing, Expo configuration, or build behavior.
