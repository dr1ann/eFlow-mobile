# Phase 2 Full Integration Implementation Plan — Department Leadership

## 1. Plan status

This plan is ready to implement. It replaces the earlier partial Phase 2 plan with a full-integration plan based on the current mobile codebase and the latest inspected upstream backend contracts.

- Mobile baseline: `b135a77e59f590b381ada919cb3a81067441acd9`
- Phase 1 baseline: the guarded full-workflow integration is committed at the mobile baseline above.
- Sequencing decision: Phase 1 is accepted as complete for beginning Phase 2 work.
- Release note: Phase 1's existing live-backend and physical-device acceptance items remain regression and release-verification checks. They do not block independent Phase 2 implementation.
- Audited upstream baseline recorded by the mobile project: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected for this plan: `042e1a5b240cf667eb3dfa69d263897686de2a04`
- Plan revised: September 2, 2026
- Existing Phase 2 state: the RLS-backed paginated project list and read-only project detail slice are already present; the full leadership workflow is not yet integrated.

The newer upstream commit is an inspection reference, not yet the mobile project's adopted compatibility baseline. Update the baseline in `AGENTS.md` and `MOBILE_IMPLEMENTATION_PHASES.md` only after the affected mobile contracts are implemented and verified against the shared non-production backend.

No migration is to be applied from the mobile repository as part of this plan. The teammate who owns the web/backend project remains responsible for applying and confirming backend changes.

## 2. Phase outcome

Phase 2 will deliver one connected, server-authorized Department Head workflow:

```text
Department Head signs in
  -> sees a scoped department overview and attention items
  -> creates a project with its initial structure
  -> creates a task linked to that project
  -> assigns contributors, an effective Task Leader, and eligible reviewers
  -> sets dependencies and supported deadlines
  -> supervises progress while employees use the Phase 1 workflow
  -> reviews work only when explicitly authorized and routed
  -> inspects project health and permission-scoped reports
  -> checks server-calculated completion readiness
  -> completes and later archives an eligible project

Optional AI branch
  -> requests a typed staffing recommendation job
  -> leaves or restarts the app while the job runs
  -> reviews and edits the returned draft
  -> explicitly confirms through the normal assignment mutation
```

The non-AI leadership workflow must remain usable when the gateway or AI host is unavailable. AI output is advisory and cannot assign people, approve work, change project state, or perform any other protected mutation by itself.

## 3. Scope

### Included

1. Department overview using live, permission-scoped metrics.
2. Virtualized, filterable task supervision views.
3. Atomic project creation with the backend-supported initial structure.
4. Project detail expansion for milestones, members, rollups, activity, and completion readiness.
5. Safe project lifecycle actions: complete and archive.
6. Basic project edits only after an atomic authorized contract exists.
7. Atomic task creation linked to a project or authorized department scope.
8. Task assignment, effective Task Leader selection, reviewer routing, dependencies, and supported deadlines.
9. Department review inbox and leading-work views that reuse the Phase 1 review lifecycle.
10. Team workload and attention views backed by narrow server contracts.
11. Permission-scoped reports with mobile filters and drill-down.
12. A typed, queued AI staffing recommendation workflow with persisted recovery and explicit human confirmation.
13. React Query caching, mutation invalidation, Realtime refresh, offline handling, and accessible mobile states for the workflows above.

### Explicitly excluded

- Budget, petty-cash, liquidation, cash-release, and other finance workflows. These remain Phase 4 or later.
- PDF or CSV report export.
- Proposal upload, PDF extraction, and AI proposal decomposition/import.
- Push-notification delivery, chat, calls, and general AI briefs. These remain Phase 3 concerns.
- Permanent project deletion.
- Project restore until an atomic authorized restore contract exists.
- Organization-wide user, role, or permission administration.
- A generic arbitrary-prompt AI interface or client-selected model.
- Desktop-style Kanban, dense data grids, and literal copies of web layouts.
- Automatic offline replay of project, task, assignment, review, or lifecycle mutations.

## 4. Supported roles and permission behavior

The app may hide or disable actions for usability, but the backend remains the authorization boundary for every protected read and mutation.

| Actor | Allowed Phase 2 behavior | Required deny behavior |
|---|---|---|
| Authorized Department Head | Manage projects and work only inside the server-authorized organization/project scope | Cannot act outside scope, self-review, or bypass lifecycle rules |
| Authorized Assistant Head | Only the operations explicitly granted by the final backend permission contract | Fails closed where assistant-head authority is undefined |
| Effective Task Leader | Manage the server-authorized task and its subtasks; review only if correctly routed | Task leadership does not grant department-wide or project-wide management |
| Assigned reviewer | Decide eligible submissions through the Phase 1 review contract | Cannot review their own work or unrelated submissions |
| Assigned contributor | Read and update only assigned work through the Phase 1 contract | Cannot manage projects, teams, reviewers, or unrelated work |
| Ordinary project member | Read the project information permitted by RLS | Membership alone does not grant management authority |
| Super Admin | Operational oversight/read-only access where the backend permits it | Cannot use mobile operational mutations merely because the client role resolver is broad |
| Unrelated, inactive, missing-profile, or unsupported account | No protected Phase 2 access | Direct routes and cached data must fail closed and clear safely |

Before enabling each action, the client must check its exact effective permission and capability gate. A successful client check never replaces RLS, an RPC authorization check, or an authenticated gateway check.

## 5. Upstream compatibility findings

The latest inspected upstream `main` is `042e1a5b240cf667eb3dfa69d263897686de2a04`. The commits since the recorded mobile audit include broad web changes, but only verified contract-relevant changes should enter the mobile implementation.

### Required compatibility work

- Adopt and verify the project completion lifecycle introduced by `20260831000003_project_completion_lifecycle.sql`:
  - `get_project_completion_readiness(project_id)`
  - `complete_project(project_id, note)`
  - `archive_completed_project(project_id, reason)`
  - database guards against direct lifecycle updates
- Verify the existing project and task RPC signatures already represented in the generated mobile database types:
  - `create_project_with_details(jsonb)`
  - `create_task_with_details(jsonb)`
  - `assign_task_with_details(...)`
  - `set_subtask_due_date(...)`
- Recheck project, task, reviewer, member, milestone, activity, report, and Realtime RLS behavior with the actual Phase 2 test identities.

### Do not adopt as a mobile contract yet

- The web's direct project update followed by a separate audit write is not atomic enough for mobile project editing.
- The web restore flow uses a direct update and separate audit event; there is no verified atomic restore RPC.
- The current generic AI job route accepts client-controlled messages and model selection. It is not an acceptable staffing-recommendation contract.
- Broad web-side report and workload aggregation should not be copied into the phone. Mobile needs narrow, paginated, permission-scoped DTOs.
- Finance-related upstream changes remain outside Phase 2.

### Privacy handling for project completion

The completion-readiness RPC may include finance-related blockers because the server protects overall project integrity. Phase 2 may show only a generic message such as “Financial clearance must be resolved on the web.” It must not expose cash amounts, receipts, liquidation details, or a mobile finance workflow.

## 6. Authoritative contract readiness

| Capability | Current contract state | Phase 2 action |
|---|---|---|
| Project list/detail | Implemented as an RLS-backed read slice | Retain, extend, and regression-test |
| Project members/milestones/activity | Schema expectations exist; mobile integration is incomplete | Confirm minimal selects, RLS, pagination, and Realtime events |
| Project creation | `create_project_with_details(jsonb)` exists | Verify scope, validation, atomic side effects, and allowed/denied identities before enabling |
| Project completion readiness | Typed RPC exists | Map a minimal DTO, redact finance detail, and live-probe allowed/denied identities |
| Project completion | Typed RPC exists | Use RPC only; block offline and duplicate/stale actions |
| Project archive | Typed RPC exists | Use RPC only after completed state; block offline and invalid states |
| Project restore | No verified atomic RPC | Keep unavailable |
| Project edit | Web behavior is direct update plus separate audit | Require an atomic authorized RPC before enabling |
| Project member/milestone mutations | Final atomic contract not established | Implement UI/forms behind disabled capability gates; enable only after contract verification |
| Task creation | `create_task_with_details(jsonb)` exists | Verify participants, dates, dependencies, audit/notification effects, and authorization |
| Task assignment | `assign_task_with_details(...)` exists | Verify contributor, leader, reviewer, project, organization, and self-review constraints |
| Subtask deadline | `set_subtask_due_date(...)` exists | Verify lifecycle and authorization before enabling |
| Task deadline | No authoritative dedicated mutation was found | Keep task-deadline editing gated until a server contract is supplied |
| Department overview | No final minimal mobile DTO confirmed | Add a paginated/scoped view or RPC rather than large client aggregation |
| Workload/attention | No final narrow mobile DTO confirmed | Add a scoped, paginated view or RPC |
| Reports | No final permission-scoped mobile report DTO confirmed | Add narrow report endpoints with filters and drill-down identifiers |
| Staffing recommendation | Existing generic AI route is unsuitable | Add a typed queued business endpoint and job ownership controls |

## 7. Development and release capability gates

Use one Phase 2 allowlist environment variable:

```text
EXPO_PUBLIC_PHASE_2_LIVE_CAPABILITIES=
```

Recognized values:

```text
departmentOverview
projectRelations
projectRealtime
projectCreate
projectComplete
projectArchive
projectEdit
projectMembers
projectMilestones
taskCreate
taskAssign
subtaskDeadline
taskDeadline
teamWorkload
departmentReports
staffingRecommendation
```

Rules:

1. Unlisted or malformed values fail closed.
2. Existing verified project reads remain available according to RLS; the allowlist controls only newly integrated capabilities.
3. Every live mutation remains off until its exact server operation passes allowed and denied identity probes.
4. Capability flags are rollout controls, not authorization controls.
5. Development fixtures may demonstrate unavailable screens and form behavior, but the UI must label them as preview data and must never claim the action succeeded on the live backend.
6. Fixtures must be impossible to enable accidentally in a production build.
7. A missing contract blocks only the dependent action, not unrelated Phase 2 packages.

## 8. Mobile architecture

### Feature modules

```text
src/
  contracts/
    phase-2/
  lib/
    phase-2/
      capabilities.ts
      permissions.ts
      errors.ts
      ids.ts
  features/
    department-overview/
    projects/
    task-management/
    team-supervision/
    reports/
    staffing-recommendations/
```

Each feature keeps these concerns separate:

- server contracts and mappers
- query keys and read hooks
- mutation services and hooks
- Realtime event mapping
- screens and reusable native components
- permission/capability presentation guards
- focused tests

Do not place server state in a large global store. TanStack Query owns remote data; only short-lived form state stays local. Persist only the minimum restart-safe AI job metadata and never persist raw private prompts or report contents.

### Navigation

Keep the native bottom navigation at no more than five items. The intended leadership layout is:

```text
Home | Inbox | Work | Manage | More
```

- `Manage` becomes the entry point for Department Head project, team, workload, and report routes.
- Existing employee/reviewer routes remain accessible through `Work` and `Inbox`.
- Notices, settings, and less frequent destinations live under `More`.
- Do not add a sixth tab for reports or AI.
- Use nested native stacks for project create/detail/lifecycle, task create/assignment, report drill-down, and staffing recommendation screens.
- Every protected route must independently resolve the signed-in profile, effective permission, server scope, and entity availability. A hidden tab is not a route authorization check.

Existing file routes should remain thin adapters that render feature screens and pass route parameters. Business logic belongs in feature modules.

## 9. Data, mutation, Realtime, and offline rules

### Query behavior

- Use stable query keys containing only non-sensitive scope and filter identifiers.
- Paginate projects, tasks, attention items, workload rows, activity, and report drill-down lists.
- Treat server response DTOs as untrusted input and map nullable or unknown values explicitly.
- Show loading, empty, stale-cache, offline, forbidden, timeout, and retry states where the screen owns them.
- Avoid retrying authorization, validation, or not-found errors.
- Safe reads may use bounded retry and refresh after reconnection.

### Mutation behavior

- Project creation, project lifecycle, task creation, assignment, deadlines, and reviews are online-only.
- Configure sensitive mutations so they do not automatically replay after reconnection.
- Do not automatically retry an unsafe mutation unless the server contract provides and honors an idempotency key.
- Disable duplicate submission while a mutation is pending.
- On success, invalidate the smallest complete set of affected detail, list, overview, workload, attention, review, and report queries.
- On failure, preserve the editable form where safe and display a redacted actionable message.
- Never present partial client-side side effects as a successful server transaction.

### Realtime behavior

- Subscribe only while an affected screen or authenticated feature scope is active.
- Map events to targeted invalidation rather than manually rebuilding complex paginated results.
- Deduplicate rapid events and refresh after reconnect.
- Dispose subscriptions on unmount, sign-out, account change, and permission loss.
- Realtime improves active-app freshness; it is not background push delivery.

### AI job behavior

- Resolve the gateway through the existing typed gateway client and attach the current Supabase bearer token.
- Create the typed job once and persist only job ID, operation type, owner ID, and safe timestamps.
- Resume polling after navigation or restart using bounded backoff.
- Support queued, running, succeeded, failed, expired, cancelled, and unavailable states when the backend exposes them.
- Stop polling when the app is backgrounded and resume on foreground.
- Never retry a job-creation mutation against a rotated endpoint without a server idempotency contract.
- The returned recommendation is an editable draft. Confirmation calls the ordinary authorized assignment mutation.

## 10. Implementation work packages

### P2-FI.0 — Contract baseline and capability framework

Implement:

- Record the inspected upstream commit and contract delta in `docs/PHASE_2_CONTRACTS.md`.
- Regenerate Supabase types only from the confirmed deployed non-production schema.
- Add the Phase 2 capability parser and fail-closed helpers.
- Add canonical Phase 2 operation checks, including explicit operational denial for Super Admin.
- Add shared Phase 2 error mapping without leaking server internals.
- Document the test identity matrix and backend environment used for acceptance.

Automated tests:

- Every recognized, empty, malformed, duplicate, and unknown capability value.
- Canonical role aliases, inactive/missing profiles, explicit denies, and privilege-escalation attempts.
- Super Admin oversight versus operational mutation behavior.
- Error mapping and sensitive-message redaction.

Exit:

- Unverified actions cannot become live through a typo or broad client role.
- The contract document matches the deployed test backend, not only the web source tree.

### P2-FI.1 — Department overview and scoped task board

Implement:

- A live Department Head overview with server-calculated counts and attention categories.
- A virtualized task board/list with status, project, assignee, leader, reviewer, deadline, and attention filters supported by the backend contract.
- Pull-to-refresh, pagination, stable sorting, and drill-down to existing Phase 1 task/subtask details.
- Clear preview mode if a temporary development fixture is required before the overview DTO exists.

Automated tests:

- Query payloads, DTO mapping, filters, sort order, pagination boundaries, and deduplication.
- Loading, empty, stale/offline, forbidden, timeout, and server-error states.
- Realtime invalidation and subscription cleanup.
- Direct route denial and removal of cached protected content after permission loss.

Live acceptance:

- Authorized Department Head sees only their effective scope.
- Unrelated, inactive, ordinary member, and Super Admin operational contexts cannot obtain management data through this route.

### P2-FI.2 — Project detail, relations, health, and activity

Implement:

- Extend the existing project detail with paginated milestones, members, linked tasks, rollup health, activity, and completion readiness.
- Add mobile-first sections instead of a desktop dashboard copy.
- Add targeted Realtime invalidation for changed project, membership, milestone, task, and lifecycle events.
- Keep private notes and finance details out of the mobile DTO.

Automated tests:

- Relation mapping, nullable values, rollup states, activity pagination, duplicate events, reconnect refresh, and cleanup.
- Member-without-management behavior.
- Deleted, archived, forbidden, and malformed deep-link destinations.
- Generic finance-blocker rendering without sensitive detail.

Live acceptance:

- Allowed roles receive only RLS-authorized project relations.
- Direct links cannot reveal metadata for unrelated projects.

### P2-FI.3 — Atomic project creation and lifecycle

Implement:

- A keyboard-safe project creation form backed only by `create_project_with_details(jsonb)` after contract verification.
- Server-authorized selection of organization scope, initial members, and supported initial milestones.
- Validation for required text, dates, duplicate members, invalid roles, stale participants, and unsupported scope.
- Completion-readiness display backed by `get_project_completion_readiness(project_id)`.
- Explicit complete and archive confirmation flows backed only by their lifecycle RPCs.
- Project edit, member mutation, milestone mutation, and restore screens may be built in preview form but remain disabled until atomic contracts pass verification.

Automated tests:

- Valid and malformed creation payloads, boundary dates, duplicates, missing scope, stale participants, and unauthorized attempts.
- Pending/disabled UI, successful invalidation, duplicate press protection, timeout, offline blocking, stale state, and server rejection.
- Every important completion-readiness blocker and invalid transition.
- Complete-before-ready, archive-before-complete, duplicate complete/archive, and Super Admin mutation denial.

Live acceptance:

- At least one authorized Department Head creation succeeds atomically.
- The same operation is denied for an ordinary member, unrelated Department Head, inactive account, and Super Admin operational context.
- Readiness, completion, and archive agree between mobile and web for the same project.
- No partial project, member, milestone, audit, or notification state is presented as success.

### P2-FI.4 — Task creation, assignment, dependencies, and deadlines

Implement:

- A project-aware task creation flow backed only by `create_task_with_details(jsonb)`.
- Participant selectors sourced from the server-authorized organization/project scope.
- Assignment through `assign_task_with_details(...)` after exact contract verification.
- Explicit effective Task Leader and reviewer routing.
- Dependency selection with cycle, duplicate, completed-state, and cross-scope validation enforced server-side and reflected in the UI.
- Subtask due-date changes through `set_subtask_due_date(...)` after verification.
- Task deadline editing remains unavailable until an authoritative server mutation exists.

Automated tests:

- Payload mapping for representative valid input and all nullable fields.
- Duplicate contributors, unsupported roles, inactive users, unrelated users, self-review, missing reviewer, invalid dates, dependency cycles, stale state, and server rejection.
- Online-only behavior, pending state, duplicate presses, invalidation, and redacted errors.
- Direct deep links and cached participant data after permission loss or sign-out.

Live acceptance:

- An authorized Department Head creates and assigns project-linked work.
- Assigned employees and reviewers see the result through the Phase 1 queries.
- Unauthorized identities cannot create, assign, reroute, or alter deadlines.

### P2-FI.5 — Team supervision, workload, attention, and review

Implement:

- Leading-work and team-workload views backed by narrow server DTOs.
- Attention categories for overdue, blocked, awaiting submission, awaiting review, and returned work without exposing unrelated personnel data.
- Department review inbox integration that reuses the Phase 1 review services and self-review protections.
- Drill-down from counts to a paginated filtered list.

Automated tests:

- Workload/attention DTO mapping, pagination, filters, stable identifiers, and privacy boundaries.
- Effective Task Leader versus ordinary member behavior.
- Assigned reviewer routing, primary/backup rules where supported, and self-review denial.
- Realtime invalidation, reconnect behavior, and cleanup.

Live acceptance:

- Counts match their drill-down lists for the same authorized identity.
- Ordinary membership never grants management or review authority.
- Review decisions remain server-authorized Phase 1 mutations.

### P2-FI.6 — Permission-scoped reports

Implement:

- Mobile report summaries for approved project and task delivery indicators.
- Server-supported date, organization, project, status, and responsibility filters.
- Drill-down identifiers that open authorized project/task screens.
- Explicit stale-data time and empty/partial-data states.
- No PDF/CSV export in Phase 2.

Automated tests:

- Filter payloads, date boundaries, DTO mapping, pagination, totals, null handling, and deterministic formatting.
- Allowed and denied permissions, out-of-scope drill-down, deleted destinations, timeout, offline, and retry behavior.
- Privacy checks that report queries and errors do not expose unauthorized personnel or finance information.

Live acceptance:

- Report totals and drill-down agree with the backend for at least one authorized department scope.
- Unrelated and inactive identities are denied by the server.

### P2-FI.7 — Typed queued staffing recommendation

Backend prerequisite:

- Provide a typed authenticated operation such as `POST /api/ai/staffing-recommendations/jobs` plus owner-scoped status and cancellation routes.
- The server derives private task, workload, and manager context from authorized IDs.
- The client cannot choose a model, send arbitrary system prompts, or retrieve another user's job.

Implement after that contract exists:

- A task-scoped request form using only permitted business inputs.
- Queued/running/succeeded/failed/expired/cancelled/unavailable UI.
- Persisted job recovery across navigation and restart.
- Editable recommendation review with reasons clearly marked as advisory.
- Explicit confirmation through the normal task-assignment mutation.

Automated tests:

- Bearer header, typed payload, URL resolution, timeout, cancellation, rotated endpoint rules, and redacted errors.
- Every supported job state, bounded backoff, background pause, restart recovery, and corrupt/expired persisted data cleanup.
- Job ownership denial, model/prompt exclusion, AI outage, and human-confirmation requirement.
- Confirmation revalidates permissions and does not directly reuse AI output as a privileged mutation.

Live acceptance:

- An authorized request survives navigation and app restart.
- Another account cannot read or cancel the job.
- AI unavailability does not block ordinary task assignment or other Phase 2 work.

### P2-FI.8 — Integration, device acceptance, and release hardening

Implement and verify:

- Cross-feature invalidation from project/task mutations into overview, workload, review, reports, and Phase 1 screens.
- Session refresh, sign-out cleanup, account switching, permission loss, and stale cached data handling.
- Large-list virtualization and realistic scrolling.
- Accessibility labels, roles, disabled states, errors, and touch targets.
- Safe areas, keyboard behavior, camera/document modules already used by Phase 1, and representative Android/iOS layouts.
- Capability documentation and final removal of development-only fixture access from production builds.

Exit:

- Every enabled capability has automated tests, allowed/denied live probes, and device evidence.
- Every disabled capability has a named backend blocker and no misleading success state.

## 11. Backend handoff requirements

For every unavailable operation, send the backend owner a narrow report containing the exact failing operation, expected permission, actual response, and minimum backend change. Do not request broad RLS disabling or a mobile service-role key.

### Required confirmations or changes

1. **Phase 2 test identities**
   - Supply active test accounts for an in-scope Department Head, out-of-scope Department Head, Assistant Head, effective Task Leader, assigned reviewer, ordinary project member, contributor, inactive user, and Super Admin.
   - Document their expected organization/project/task relationships.

2. **Project creation hardening**
   - Confirm `create_project_with_details(jsonb)` validates management scope and performs all required project, initial member/milestone, audit, and notification effects atomically.

3. **Project edit/member/milestone contracts**
   - Add narrow authorized RPCs or one versioned atomic project-management RPC.
   - Reject stale state, invalid participants, cross-scope changes, and unauthorized roles in the server.

4. **Project lifecycle verification**
   - Confirm the deployed signatures and RLS for readiness, complete, and archive.
   - Return structured blocker codes safe for mobile display.
   - Keep finance blocker details private and provide only a safe category/message to mobile.
   - Add an atomic restore RPC only if restore is approved for mobile.

5. **Task creation and assignment hardening**
   - Confirm project/organization scope, participant eligibility, effective Task Leader, reviewer routing, self-review prevention, dependency validation, dates, audit events, and notifications are enforced atomically.

6. **Task deadline contract**
   - Provide a narrow authorized task-deadline RPC if task-level deadline editing is required in Phase 2.

7. **Department overview, workload, attention, and reports**
   - Provide narrow, paginated, permission-scoped RPCs or views with stable DTOs.
   - Avoid returning broad personnel rows when aggregate values or scoped drill-down IDs are sufficient.

8. **Realtime publication and policy**
   - Confirm the exact tables/events available to each authorized identity and that unrelated changes are not delivered.

9. **Typed staffing recommendation queue**
   - Replace the generic client-controlled AI contract for this workflow with authenticated typed routes.
   - Enforce operation permission, resource scope, owner-only job reads, model allowlisting, input/output limits, rate limits, timeouts, cancellation, audit events, and safe context assembly.
   - Return a draft only; never call assignment or another protected mutation from the AI job.

## 12. Planned test locations

Use colocated tests and existing repository conventions. Final filenames may be adjusted to match the implemented module names.

```text
src/lib/phase-2/capabilities.test.ts
src/lib/phase-2/permissions.test.ts
src/lib/phase-2/errors.test.ts
src/features/department-overview/department-overview-query.test.ts
src/features/department-overview/screens/department-overview-screen.test.tsx
src/features/projects/project-relations-query.test.ts
src/features/projects/project-lifecycle.test.ts
src/features/projects/screens/project-create-screen.test.tsx
src/features/projects/screens/project-detail-screen.test.tsx
src/features/task-management/task-create.test.ts
src/features/task-management/task-assignment.test.ts
src/features/task-management/screens/task-create-screen.test.tsx
src/features/task-management/screens/task-assignment-screen.test.tsx
src/features/team-supervision/workload-query.test.ts
src/features/team-supervision/screens/team-workload-screen.test.tsx
src/features/reports/department-reports-query.test.ts
src/features/reports/screens/department-reports-screen.test.tsx
src/features/staffing-recommendations/staffing-job-client.test.ts
src/features/staffing-recommendations/staffing-job-persistence.test.ts
src/features/staffing-recommendations/screens/staffing-recommendation-screen.test.tsx
```

Add integration checks against an explicitly configured non-production Supabase/gateway environment for server authorization and lifecycle behavior. Automated unit tests must continue to use controlled mocks and must never connect to production services.

## 13. Required validation

During implementation:

```powershell
npm test -- --runTestsByPath <directly-affected-test-file>
```

After every executable source or test change:

```powershell
npm run check
```

After routing, Expo configuration, assets, dependencies, build scripts, or native integration change:

```powershell
npm run build:verify
```

Also perform contract acceptance against the shared non-production backend with at least one allowed and one denied identity for every sensitive RLS/RPC/gateway operation. Never point automated unit tests at production Supabase, Storage, the gateway, or the AI host.

If a command or live probe cannot run, record the exact command/operation, why it was unavailable, and the next-best verification. Do not mark it passed.

## 14. Manual Android and iOS acceptance

Verify on representative Android and iOS devices or suitable simulators:

- Department Head navigation remains within the five-tab limit and all nested routes are reachable.
- Safe areas, keyboard avoidance, scroll behavior, orientation assumptions, contrast, and touch targets.
- Project and task create forms with long names, validation errors, participant selection, and interrupted network access.
- Large project, task, activity, workload, attention, and report lists remain responsive.
- Background/foreground refresh and Realtime reconnection.
- Sign-out, account switching, stale-session recovery, and direct unauthorized deep links.
- Duplicate mutation prevention and clear offline blocking.
- Project readiness, complete, and archive confirmations.
- Phase 1 employee submission and reviewer behavior after Phase 2 creates and assigns work.
- AI job backgrounding, restart recovery, cancellation, expiry, outage, and explicit confirmation.
- No sensitive project, personnel, report, finance, token, or AI context appears in logs or generic error messages.

## 15. Completion criteria

Phase 2 full integration is complete only when all of the following are true:

1. An authorized Department Head can create a real project through an atomic server contract.
2. The Department Head can create and assign linked work with valid contributors, an effective Task Leader, eligible reviewers, dependencies, and supported deadlines.
3. Assigned users can continue that work through the live Phase 1 submission and review lifecycle.
4. Department overview, task supervision, workload, attention, project health, activity, and reports use live permission-scoped data.
5. Project completion readiness, completion, and archive use the server lifecycle RPCs and agree with web behavior.
6. Ordinary membership, unrelated scope, inactive accounts, self-review, and Super Admin operational mutations are denied by the authoritative server contract.
7. All sensitive mutations are online-only, atomic, correctly invalidated, and never silently replayed.
8. Realtime subscriptions refresh active screens without leaking scope and are cleaned up correctly.
9. The staffing recommendation uses a typed, owner-scoped queued endpoint; its output remains an editable draft requiring normal authorized confirmation.
10. AI outage does not block non-AI Phase 2 workflows.
11. Budget, petty-cash, PDF/CSV export, project restore, and other deferred work remain outside the completion claim.
12. Targeted tests, `npm run check`, and applicable `npm run build:verify` pass.
13. Allowed and denied live-backend probes pass for every enabled sensitive operation.
14. Android and iOS acceptance evidence is recorded, including Phase 1 regression through Phase 2-created work.
15. `AGENTS.md`, `MOBILE_IMPLEMENTATION_PHASES.md`, `docs/PHASE_2_CONTRACTS.md`, environment examples, and the audited upstream baseline are synchronized with verified reality.

## 16. Recommended implementation order

```text
P2-FI.0 contract baseline and capability framework
  -> P2-FI.1 department overview and scoped task board
  -> P2-FI.2 project detail, relations, health, and activity
  -> P2-FI.3 atomic project creation and lifecycle
  -> P2-FI.4 task creation, assignment, dependencies, and deadlines
  -> P2-FI.5 team supervision, workload, attention, and review
  -> P2-FI.6 permission-scoped reports
  -> P2-FI.7 typed queued staffing recommendation
  -> P2-FI.8 cross-feature and device acceptance
```

Backend work may proceed in parallel, but each mobile action is enabled independently only after its contract and test identities are ready. The first shippable vertical checkpoint is project creation through assigned Phase 1 work; reports and AI must not delay that checkpoint.
