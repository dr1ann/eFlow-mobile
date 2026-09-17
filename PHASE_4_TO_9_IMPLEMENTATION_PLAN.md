# Phases 4–9 — Complete the mobile capstone flow

## Plan status

- Created: September 6, 2026, following the user's request to start the next implementation phases at Phase 4.
- Status: P4.1–P4.4 are implemented in the workspace on September 8, 2026. P4.5 remains open until real non-production identities and Android/iOS evidence opening are verified; Phase 4 exit criteria are not yet accepted.
- Basis: [source readiness assessment](docs/CAPSTONE_FLOW_READINESS.md), mobile commit `71a2a9b98f00b0484ba6de237f0b5f6c643bb53a`, and inspected web commit `042e1a5b240cf667eb3dfa69d263897686de2a04`.
- Adopted web compatibility baseline remains `508aabc8881630b37a62a973645ecb0bb386e99e`.
- Canonical scope and security rules: [mobile roadmap](MOBILE_IMPLEMENTATION_PHASES.md) and [repository instructions](AGENTS.md).

These phases finish gaps in the existing implementation. Phases 0–3 retain their original scope and open exit criteria; later numbering does not imply earlier completion. Reuse existing adapters, contracts, query helpers, routes, and design tokens. Do not rebuild working foundation code.

## Delivery sequence and defense milestones

| Phase | Outcome | Defense relevance | Depends on |
| --- | --- | --- | --- |
| 4 | Evidence can be inspected; feedback, resubmission, and approval form a complete online loop | Required | Existing authentication, work, submission, and review foundation |
| 5 | Employees and Task Leads can find their work and navigate projects/tasks/subtasks | Required | Existing work/project reads; integrates Phase 4 history |
| 6 | A Department Head creates and assigns work; a Task Lead creates and assigns subtasks on mobile | Required for a demo that starts entirely on mobile; can follow the first web-assisted demo | Phase 5 navigation and verified planning contracts |
| 7 | State transitions, refresh, interrupted submissions, and access changes recover correctly | Required | Phases 4–5; include Phase 6 mutations when implemented |
| 8 | The core flow is polished, verified on the demonstration device, and rehearsed | Required; core mock-defense milestone | Phases 4–5 and 7; Phase 6 if mobile planning is included |
| 9 | One real AI operation can be demonstrated with human review and outage recovery | Optional unless required by the rubric | Phase 8 core milestone and a confirmed typed AI contract |

Recommended first defense sequence: **4 → 5 → 7 → 8**, with work prepared on the web. For a creation-to-completion mobile demonstration: **4 → 5 → 6 → 7 → 8**. Add Phase 9 if the rubric requires it. Phase 6 remains planned mobile scope even when it is omitted from the first rehearsal.

Begin allowed/denied backend checks during Phase 4 and continue them with each affected phase. Phase 8 collects and rehearses the evidence; it is not the first time integration testing should happen. Unavailable live contracts gate only their specific operations, while independent UI, pure logic, and controlled-fake tests can proceed.

## Shared implementation and verification rules

- Track development, live integration, and device acceptance separately. Existing enabled local flags are not proof of backend acceptance; do not infer deployment failures merely from an old blocker report either.
- Before adopting changed web behavior, recheck upstream and compare with the recorded/inspected commits. Record relevant RPC, RLS, Storage, notification, and lifecycle contracts. Never blindly push migrations or replace the baseline based only on source inspection.
- Use the assigned contributor, effective Task Lead, and stored reviewer relationships. Task Lead precedence remains `assigned_to`, then `recommendation_lead_id` only when unassigned. Do not add new supported roles or widen Assistant Head/Super Admin scope under this plan.
- Use the agreed non-production environment and securely supplied test accounts. Record environment, source SHA, relationship, operation, and sanitized outcome. Do not put credentials or private evidence in reports.
- Keep approvals and other sensitive mutations online-only. Do not replay them automatically after reconnect. RLS/RPC/Storage/server routes remain the security boundary.
- Tests belong in each implementation change. Add regression tests that fail for the previous defect; test user-visible behavior, failure paths, authorization, and cleanup rather than private internals.
- Run the affected test file during development, then `npm run check` after executable/test changes. Also run `npm run build:verify` after route, Expo configuration, asset, dependency, build-script, or native integration changes.
- Verify affected native behavior on Android and iOS, or record the exact platform limitation. An export is not installed-device acceptance.
- After each slice, update the parity matrix, roadmap status, this plan's progress checklist, and relevant contract notes. Keep earlier phase criteria open until their own evidence exists.

## Phase 4 — Evidence review, feedback, and resubmission

### Goal

An assigned employee submits evidence, the routed reviewer inspects it and requests changes, and the employee submits a corrected version that can be approved. The Task Lead then submits the parent task to its routed reviewer.

### Existing implementation to extend

- [Task review screen](src/features/reviews/screens/task-review-screen.tsx) and [subtask review screen](src/features/reviews/screens/subtask-review-screen.tsx).
- [Task query helpers](src/features/tasks/query-options.ts), [subtask query helpers](src/features/subtasks/query-options.ts), and [evidence storage adapter](src/features/subtasks/evidence-storage.ts).
- [Task detail](src/features/tasks/screens/task-detail-screen.tsx), [subtask detail](src/features/subtasks/screens/subtask-detail-screen.tsx), and existing submission/decision adapters.

### Implementation slices

1. **P4.1 — Read the submission:** display note, author, submitted time, version, decision state, and attached-file metadata. Fetch attachments for the selected submission rather than mixing attempts. Handle loading, missing/hidden records, empty optional parent evidence, and read failures explicitly.
2. **P4.2 — Inspect private evidence:** connect the existing signing helper to native file opening. Obtain a fresh short-lived link on an authorized open; handle expiry, unavailable files, cancellation, and retry. Never persist a signed URL or substitute a public bucket URL. Verify native URI handling for the file types chosen for the defense.
3. **P4.3 — Follow corrections:** add employee-visible task/subtask submission history, reviewer feedback, and progress history. Provide a clear resubmit action for eligible work; retain immutable version 1 when version 2 is submitted. Validate required notes and file rules before uploading.
4. **P4.4 — Finish decision interaction:** disable both decision actions during a pending mutation, require feedback for changes, preserve self-review/stored-reviewer checks, and display canonical status after the decision. A server rejection must not appear as success.
5. **P4.5 — Verify the normal online loop:** use real contributor/lead/reviewer records to inspect actual evidence, request changes, resubmit, approve subtasks, submit the parent, and approve it. Record private-storage and wrong-reviewer denials alongside success.

### Implementation progress — September 8, 2026

- [x] **P4.1:** Task and subtask review surfaces now show the canonical latest pending attempt’s note, author, UTC timestamp, version, status, and only that attempt’s attachment metadata. Metadata reads handle loading, retryable failures, missing current attempts, and empty optional parent evidence.
- [x] **P4.2:** A press obtains rules and a fresh private signed URL, then opens it with Expo Linking. URLs never enter rendered state, query cache, or persistence; signing/open failures and cancellation are redacted and retryable.
- [x] **P4.3:** Task/subtask details show versioned attempts and reviewer feedback; subtask details show progress history. Requested-change subtasks use an explicit resubmit label. A requested-change parent uses the server-required Resume work transition before another submission. Blank completion notes now fail before any upload.
- [x] **P4.4:** Both decision buttons and feedback input lock during a mutation. Client eligibility retains stored reviewer/self-review UX checks, while the server response is written to the scoped detail cache before navigation.
- [ ] **P4.5:** No agreed non-production accounts, backend receipts, or Android/iOS device session were available in this workspace. Run the documented live workflow and denial checks before claiming Phase 4 acceptance.

The confirmed task rework contract is `changes_requested → in_progress → submit_task_for_review`; do not add a direct parent resubmit from `changes_requested`. See [Phase 4 contract notes](docs/PHASE_4_CONTRACTS.md).

### Tests and manual verification

Add `task-review-screen.test.tsx` and `subtask-review-screen.test.tsx` under `src/features/reviews/screens/`. Extend the existing detail, storage, and submission tests; add submission-screen tests where validation/navigation changes. Cover attempt-specific attachments, expired links, hidden records, feedback display, version selection, pending actions, failed decisions, self-review, and eligible/forbidden resubmission. Use controlled fakes for automated tests.

Manually open the real demonstration files on the affected native platforms. Prove allowed and denied Storage/RPC behavior with real user identities in the agreed test backend.

### Exit criteria

- [ ] A reviewer can read the completion note and open the actual evidence for the selected attempt.
- [ ] The employee can see requested changes, resubmit, and distinguish previous and current attempts.
- [ ] Subtask approval and parent review produce the expected shared server state.
- [ ] Self-review, wrong-reviewer, and unrelated-file access are denied.
- [ ] Applicable automated tests and native file-opening checks pass, or the exact device limitation is recorded.

This phase establishes the normal online loop. Phase 7 still owns interruption/reconnect hardening; Phase 1 is not declared fully accepted merely because Phase 4 is implemented.

## Phase 5 — My work, leading work, deadlines, and project navigation

### Goal

Every demo participant can find the work they are responsible for, understand its state and deadline, and move between its project, task, subtask, and history.

### Existing implementation to extend

[Work screen](src/features/tasks/screens/work-screen.tsx), task/subtask query helpers, [project detail](src/features/projects/screens/project-detail-screen.tsx), and existing guarded routes. My Subtasks and leading-task reads already exist; their dedicated list UI does not.

### Implementation slices

1. **P5.1 — Work views:** connect My Tasks, My Subtasks, and Work I am Leading with stable IDs, pagination, refresh, loading/empty/error/offline states, and accessible controls. An actual subtask assignee must not depend on membership in the parent task's client-side team filter to discover assigned work.
2. **P5.2 — Useful filters:** support active, waiting/blocked where backed by authoritative readiness, changes requested, awaiting review, and completed work. Filter/paginate correctly across the entire authorized result set; an empty filtered page is not proof that no later match exists.
3. **P5.3 — Deadlines:** add due-soon/overdue navigation from authorized work. Define the date/time-zone behavior and test midnight boundaries; do not silently treat UTC as the user's local date. Label partial list counts rather than presenting them as organization totals.
4. **P5.4 — Project drill-down:** show authorized linked tasks under a project, link task detail back to its project, and preserve task → subtask → history navigation. Handle deleted and RLS-hidden destinations without revealing record existence.

### Implementation progress — September 15, 2026

- [x] **P5.1:** The Work tab now offers virtualized My Tasks, My Subtasks, and Work I am Leading views with stable ID de-duplication, status filtering, refresh, retry, cached/offline notices, partial-page counts, explicit load-more controls, and accessible rows. My Subtasks reads direct assignee fields rather than filtering through a parent-task team in the client.
- [x] **P5.2:** Task and subtask status filters now run in the RLS-backed database query before pagination. The Waiting task filter is limited to the persisted `pending_assignment` state; the client no longer presents dependency state inferred from a partial page as authoritative blocking.
- [x] **P5.3:** Work views provide loaded-item Overdue and Due in 7 days navigation. Date-only values use the device's local calendar date; timestamps convert to the device's local calendar date. The UI labels loaded counts and explains that deadline views are not organization totals.
- [x] **P5.4:** Project drill-down queries only `tasks.linked_project_id`, never legacy `project_id`. Project → task and task → project navigation remain permission-gated in the client and re-read the destination under RLS, with one generic unavailable state for deleted and hidden records.
- [ ] **P5 acceptance:** No designated non-production records, assignee-only RLS receipt, or installed Android/iOS session was available in this workspace. The direct-subtask-assignee probe must confirm that deployed RLS permits an assignee who is not otherwise visible through the parent task before this phase is accepted.

See [Phase 5 contract notes](docs/PHASE_5_CONTRACTS.md) for the canonical project relation, device-local deadline policy, and deployment probes.

### Tests and manual verification

Extend `src/features/tasks/screens/work-screen.test.tsx`, task/subtask query tests, task/deadline selector tests, and project/detail tests. Add component tests next to any new list screens. Cover a contributor assigned only at subtask level, actual versus stale recommended lead, empty and later-page filter matches, duplicates, stable sorting, deadline boundaries, unauthorized/deleted links, and refresh errors with cached data.

Inspect scrolling and touch targets with a realistically large test dataset. Run `npm run build:verify` for added/changed routes.

### Exit criteria

- [ ] Contributor, Task Lead, and reviewer can reach their relevant work without manually entering an ID.
- [ ] Lists, filters, deadlines, and pagination produce accurate results across pages.
- [ ] Project/task/subtask links recheck access and handle unavailable records safely.
- [ ] Loading, stale, empty, offline, and failure states are usable on the demonstrated platform.

## Phase 6 — Mobile task planning and delegation

### Goal

A Department Head creates and assigns a task on mobile; the effective Task Lead divides it into assigned subtasks that employees can execute through Phases 4–5.

This phase is required when the defense claims work can be created entirely on mobile. Web preparation remains available for the earlier core system demonstration.

### Contract and ownership boundary

Reuse the existing project-create flow. Confirm `create_task_with_details`, `assign_task_with_details`, project links, deadlines, reviewer routing, eligible people, and subtask-management authorization before wiring live mutations. Check [Phase 2 contracts](docs/PHASE_2_CONTRACTS.md) and the [backend handoff](PHASE_1_TO_3_BACKEND_BLOCKER_REPORT.md). A generated type alone does not prove management scope or atomic side effects.

### Implementation slices

1. **P6.1 — Create a task:** provide title, description, approved project linkage, priority, schedule, acceptance criteria, and definition of done through the verified atomic contract. Make server validation, failure, and successful navigation clear.
2. **P6.2 — Assign responsibility:** select the eligible Task Lead, contributors, and primary/backup reviewers from a permission-scoped source. Preserve server-derived organization/ownership and self-review restrictions. Verify atomic assignment, audit, and notification behavior.
3. **P6.3 — Manage subtasks:** let only the effective Task Lead create, assign, schedule/order, and adjust supported execution rules. Prevent invalid membership removals, deadline violations, dependency cycles/bypasses, and stale edits through the authoritative contract. Do not invent a replacement write path if a required operation is missing.
4. **P6.4 — Connect to execution:** return new work to the correct project/work views, notify the real assignees, and execute one newly created work plan through the Phase 4 review loop.

Broader project administration, full organization management, reports, manual proposal authoring, and finance are outside this bounded planning slice.

### Tests and manual verification

Add colocated form/component tests and mocked API payload tests for the new task/subtask management code. Cover valid creation, required fields, malformed IDs, deadlines, stale writes, duplicate presses, unavailable people, missing permissions, wrong organization, ordinary-member denial, inactive actors, Task Lead precedence, self-review collisions, partial failure, cache invalidation, and offline rejection. Verify allowed/denied atomic RPC behavior against the agreed backend.

Run the full quality command and native exports. Test keyboard reachability, participant selection, and new-work discovery on the demonstrated devices.

### Exit criteria

- [ ] Head → Task Lead → contributor delegation works from mobile using real records.
- [ ] Created work enters the existing execution and review loop without manual database repair.
- [ ] Unauthorized people and roles cannot manage tasks or subtask structure.
- [ ] Related mutation, audit, notification, and failure results are verified; sensitive writes never queue offline.

## Phase 7 — Workflow correctness, synchronization, and recovery

### Goal

The demonstrated workflow remains understandable and safe when data is stale, another user acts, connectivity drops, or the app restarts.

### Implementation slices

1. **P7.1 — Readiness and failure reasons:** treat loading/failed subtask reads as unknown parent readiness. Resolve dependencies/prerequisites through authorized complete data or a verified server result, not just the current task page. Explain missing reviewer routes and known state/permission errors with redacted user messages. Keep server guards authoritative.
2. **P7.2 — Submission-attempt recovery:** preserve a safe account/environment-scoped attempt identifier and only necessary recovery metadata before uploads. Re-fetch the canonical attempt after a lost response before permitting another submission. Handle corrupt/expired persistence, restart, account switch, and sign-out without retaining private notes or signed URLs. Preserve finalized evidence; use the existing claim-before-remove cleanup and never delete on an ambiguous outcome.
3. **P7.3 — Refresh the right screens:** add focus/reconnect refresh or appropriately scoped subscriptions for Work, review inbox, and task/subtask detail/review destinations. Deduplicate incoming events, invalidate affected caches, dispose subscriptions, and handle access revocation. Surface stale data and refresh failures instead of silently claiming freshness.
4. **P7.4 — Complete inbox behavior:** wire review pagination and partial-load recovery. Verify recipient-only notification read/write and mark-all semantics. Retain canonical recipient lookup on open; add exact subtask/review destinations only if the authoritative payload supports them. Otherwise preserve the supported task link with clear navigation.
5. **P7.5 — Exercise failures with two clients:** record mobile submission → reviewer update → employee decision update, and test reconnect, lost response, duplicate decisions, unrelated/inactive access, and account switching. Include Phase 6 creation/assignment if it is in the demo.

Backend/web follow-ups include their direct-delete cleanup callers and abandoned-upload worker ownership. Report any remaining orphan-cleanup limitation explicitly; do not represent the mobile helper as a complete server cleanup service. Financial completion blockers still require legitimate web clearance or non-financial demo work.

### Tests and manual verification

Add/extend `task-submit-screen.test.tsx`, `subtask-submit-screen.test.tsx`, and `subtask-progress-screen.test.tsx` in their screen folders; `review-inbox-screen.test.tsx` under reviews; and existing readiness, submission-lifecycle, storage, query, notification-navigation, Realtime, and auth tests. Add tests for any new recovery persistence module.

Required cases include unavailable readiness data, dependencies outside the current page, empty progress input, note validation before upload, interrupted upload, committed-but-lost response, finalized cleanup denial, restart recovery, corrupt persistence, stale tokens, duplicate events, last-page behavior, and no automatic offline replay. Use real-user two-client integration checks separately from mocked tests.

### Exit criteria

- [ ] Unknown readiness cannot be shown as ready; blocked work has a useful explanation.
- [ ] An uncertain submission can be reconciled without duplicate uploads or loss of finalized evidence.
- [ ] Relevant changes reach active/focused clients and recover after reconnect without restarting the app.
- [ ] Inbox pagination, recipient state, navigation, and permission changes behave correctly.
- [ ] Fault/recovery and allowed/denied outcomes are recorded for every operation in the chosen demo.

## Phase 8 — Native presentation and mock-defense acceptance

### Goal

Deliver a coherent mobile experience and a repeatable, honest defense demonstration of the verified core workflow.

### Implementation slices

1. **P8.1 — Actionable Home:** replace the Phase 0 diagnostic landing content with authorized next actions, due work, pending reviews, and Inbox shortcuts. Move diagnostics to Settings/development surfaces. Use the existing visual system; this phase does not approve an unrelated final redesign.
2. **P8.2 — Accurate presentation:** remove stale disabled/preview copy where live behavior is enabled and accepted, integrate evidence selection with the actual submission form, and show meaningful people/status/date/success feedback. Clearly label any development-only surface; do not present synthetic chat as live messaging.
3. **P8.3 — Native acceptance:** verify safe areas, keyboard handling, back navigation, touch targets, contrast, loading/error layouts, large lists, picker cancellation/permissions, file opening, sessions, background/resume, and account switching. Test Android and iOS or document the exact untested platform and limit completion claims accordingly.
4. **P8.4 — Prepare the rehearsal:** document the agreed environment, build/source revisions, account relationships, authorized test records, sample files, expected transitions, and recovery steps without credentials. Keep a separately prepared second example so rehearsal does not require deleting history or resetting production data.
5. **P8.5 — Run and record:** execute the script below on the actual demo build/device. Record backend/device outcomes and remaining limitations in a dedicated acceptance record; update earlier phase exit criteria only where evidence now supports them.

### Defense script and acceptance criteria

- [ ] Prepare the project, task, assignments, and two subtasks through verified web workflows, or through Phase 6 when claiming mobile planning.
- [ ] Employee signs in on mobile, finds assigned work, records progress, and submits actual evidence.
- [ ] Task Lead opens evidence and requests a specific correction.
- [ ] Employee sees feedback/history, submits version 2, and receives approval.
- [ ] Once all required subtasks are approved, Task Lead submits the parent; the routed Head reviews and approves it.
- [ ] Mobile and web show the same result and notification. Show project closeout only when its verified server readiness allows it.
- [ ] Demonstrate session restoration, reconnect recovery, and a denied self/unrelated-user operation.
- [ ] Rehearse a second complete run using the prepared example. Record any stage still using web setup and any platform limitation.

### Tests and release evidence

Add/update Home, More/Settings, evidence, and affected screen tests for behavior/accessibility/navigation changes. Static token edits need visual checks rather than meaningless unit tests. Run `npm run check`; run `npm run build:verify` for changed native/build/navigation behavior and record fresh exports for the selected demo revision.

Create a sanitized acceptance record such as `docs/CAPSTONE_ACCEPTANCE.md` during implementation. Include exact commands/results, backend contract observations, device/OS/build, scenario outcomes, and remaining issues. Store distribution, signing, or paid hosting changes require their own applicable instructions and are not authorized by this planning document.

The core mock-defense milestone is reached only after the chosen flow passes this phase's checks. It does not claim full 70% parity, complete advanced Phase 3 scope, or production readiness.

## Phase 9 — One AI-assisted capstone extension

### Goal

If the rubric requires an AI demonstration, add one real, permission-scoped operation with an inspectable result, human review, and useful failure/recovery behavior.

Default candidate: a staffing recommendation for authorized work. Confirm its business contract first; a scoped management brief may be selected instead if that is the established rubric/contract. Build one, not both as an assumed requirement. An existing verified web AI operation can serve the system demonstration, but that does not complete mobile Phase 9.

### Implementation slices

1. **P9.1 — Confirm the business endpoint:** identify the authenticated gateway operation, input/result types, ownership, server-assembled private context, model allowlist, limits, audit behavior, and host availability. Do not invent an endpoint or count the generic chat proxy as this contract.
2. **P9.2 — Submit and resume a job:** reuse existing safe job-ID persistence and bounded backoff, show the contract's queue/running/failure states, and resume after navigation or restart. Persist only necessary safe identifiers; stop polling appropriately on background/sign-out.
3. **P9.3 — Review the result:** distinguish observations from suggestions and show AI output as a draft. Any assignment application requires explicit human confirmation and the verified Phase 6 mutation contract. If application remains on web, label that boundary accurately.
4. **P9.4 — Prove availability and failure:** execute a real scoped job and a denied/unavailable scenario. Ordinary task/project operations must remain usable when the gateway or AI host is unavailable.

### Tests and exit criteria

Test bearer headers, typed payloads, ownership/role denials, private-context exclusion, malformed results, bounded polling, expiry, restart, account switch, cancellation where supported, rotated endpoints, and AI-host failure. Test that model/private context is not client-controlled and that a result cannot trigger an automatic assignment or approval.

- [ ] One confirmed live business operation returns a real, authorized result on mobile.
- [ ] The job survives navigation/restart and handles unavailable/failed results usefully.
- [ ] Recommendations remain drafts; any operational application is explicit and server-authorized.
- [ ] The AI outage path leaves ordinary work operational.
- [ ] Live/device evidence is recorded separately from shared utility tests or a gateway-health check.

## Deferred work and numbering

Budget, petty cash, funding, receipts, liquidation, and other financial mutations remain outside these capstone phases. They have **no assigned implementation phase** and require a future stable-contract audit and explicit product decision. The older “Phase 4 or later” finance placeholder is superseded by this numbering; Phase 4 now means evidence review and resubmission.

Live chat, push delivery, PDF proposal import, broad reports, calls, and desktop administration are not prerequisites for the minimum core defense. Their original backlog remains available for a later explicit priority decision. Nothing here introduces an authorization bypass, offline approval queue, direct private-AI access, or a production deployment commitment.

## Planning-change verification

This file and its roadmap references are documentation-only. Tests added/updated: none. Tests: not applicable; validate phase numbering, dependencies, relative links, source filenames, command names, and scope consistency. Runtime checks from the September 6 source assessment are historical evidence, not new runs for this planning change.
