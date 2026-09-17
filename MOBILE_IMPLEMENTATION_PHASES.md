# eFlow Mobile Implementation Phases

## Roadmap status

- Status: In progress
- Mobile stack: Expo, React Native, and TypeScript
- Web upstream: [Rivaly-Kun/eFlow-e-Governance-Project](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project)
- Web audit baseline: [`508aabc8881630b37a62a973645ecb0bb386e99e`](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/commit/508aabc8881630b37a62a973645ecb0bb386e99e)
- Latest upstream `main` inspected: `042e1a5b240cf667eb3dfa69d263897686de2a04`; this is not yet the adopted mobile baseline
- Baseline date: August 27, 2026
- Current source-based demo assessment: [Mock capstone flow readiness, September 6, 2026](docs/CAPSTONE_FLOW_READINESS.md). This separates implemented/local-enabled actions from deployed and device acceptance; it does not change phase scope or the adopted baseline.
- Phase 4 implementation: P4.1–P4.4 are implemented in the workspace; P4.5 still requires non-production allowed/denied workflow and installed-device evidence checks. The [Phases 4–9 implementation plan](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md) records the remaining acceptance work before Phase 5 begins.

## Scope principle

The mobile target is not a literal reuse of 70% of the web screens or source code. React Native cannot directly reuse most HTML, CSS, Radix, MUI, browser navigation, PDF, rich-text, and drag-and-drop UI code.

The target is:

> Deliver approximately 70% of the completed, production-backed, high-frequency user journeys from the web system in a mobile-appropriate form.

A feature counts toward mobile parity only when it has a real data source, authorization rules, backend or Supabase contract, error handling, and an end-to-end workflow. Hard-coded demonstration dashboards do not count as completed features.

## Guiding rules

1. Preserve Supabase RLS, database RPCs, role permissions, task lifecycle rules, and FastAPI payload contracts.
2. Redesign screens for mobile instead of copying the desktop layout.
3. Keep business logic separate from UI so the future redesign can be adopted without rewriting data integration.
4. Implement one complete vertical workflow at a time.
5. Treat the server and database as authoritative; client permission checks are only UI guidance.
6. Never place the Supabase service-role key, internal AI key, database URL, or SMTP credentials in the mobile app.
7. Do not queue sensitive approvals, financial mutations, or permission changes for offline execution.

## Phase 0 — Mobile foundation

### Goal

Create a stable native shell and shared integration layer before implementing product features.

### Scope

- Scaffold the Expo and TypeScript application.
- Configure Expo Router with authentication and protected route groups.
- Create role and permission route guards.
- Configure Supabase Auth with mobile-safe persistent session storage.
- Use SecureStore for sensitive session material.
- Add a typed Supabase client using only the public anon/publishable key.
- Generate TypeScript database types from the deployed Supabase schema.
- Add a typed FastAPI gateway client with:
  - Supabase bearer-token authentication.
  - Absolute endpoint resolution.
  - Request timeouts and cancellation.
  - Typed HTTP and network errors.
  - One retry when the published tunnel endpoint rotates.
- Add TanStack Query for caching, mutations, invalidation, and loading/error states.
- Add foreground Supabase Realtime subscription helpers.
- Establish shared design tokens without copying the unfinished web UI.
- Add unit-test, lint, type-check, and build commands.
- Record the web baseline commit and feature parity matrix in the mobile repository.

### Suggested module boundaries

```text
app/
  (auth)/
  (tabs)/
  _layout.tsx
src/
  components/
  contracts/
  features/
    auth/
    tasks/
    subtasks/
    reviews/
    projects/
    notifications/
    announcements/
    settings/
  lib/
    gateway/
    query/
    supabase/
  theme/
```

### Exit criteria

- A user can sign in, restore a session after restarting the app, and sign out.
- An inactive or missing profile is rejected with a useful message.
- The app resolves the canonical eFlow role and effective permissions.
- Protected screens cannot be opened through a direct deep link without authorization.
- The app can perform one authenticated Supabase query and one authenticated gateway health request.
- No server-only secret appears in the mobile bundle.

## Phase 1 — Employee and Team Leader MVP

### Goal

Deliver the most frequent mobile workflow: receiving work, performing it, attaching evidence, and sending it through review.

### Active testing boundary — August 31, 2026

Phase 1 is **not complete**, and its exit criteria below remain open. A guarded integration slice is now implemented:

- An authenticated user with `navigation.tasks` can open paged task/subtask lists and details, plus the implemented start/resume, `0..99%` progress, private subtask/parent evidence submission, reviewer-inbox, and review routes when their corresponding live capability is enabled. Task/subtask reads and all protected routes remain subject to Supabase RLS.
- The implementation uses the generated task state/progress/submission/review RPCs, server-owned evidence rules, UUID attempt paths, array-buffer upload with `upsert: false`, short-lived signed reads, and claim-before-remove cleanup. It never deletes candidate evidence after an ambiguous timeout/offline/duplicate result.
- Recipient notification read writes, recipient announcements, text-only task comments, and task-scoped foreground Realtime adapters/screens are implemented separately. Super Admin has no mobile operational-review shortcut; a stored primary/backup review route is required.
- Native bottom navigation is capped at five items to satisfy `react-native-screens` on Android. Reviews, Notices, and Settings are permission-gated stack destinations under More, not additional bottom tabs.
- Every new live surface is controlled by an explicit per-operation `EXPO_PUBLIC_PHASE_1_LIVE_CAPABILITIES` allow-list and defaults off. This is only UX/release control: RLS, Storage policies, triggers, and RPCs remain the authorization boundary.
- `src/contracts/database.types.ts` was regenerated on August 31, 2026 against the configured project and now includes `get_task_evidence_rules` and `claim_task_evidence_cleanup`. The committed `20260831000001_task_evidence_security.sql` matches web `main`; the teammate reports it is deployed. No migration was applied from mobile.

There is deliberately no authorization bypass. Development fixtures, if added, must be explicit and development-only; exact non-production identities are preferred for integration work. Each live Storage/RPC/read/write capability remains disabled until its own allowed/denied probe passes. Do not disable RLS, use a service-role key, make the bucket public, or report fixture-backed behavior as live integration. The earlier linked Supabase CLI migration list was empty; this remains an auditability problem, not proof that the deployed schema is missing, and the mobile repository must not repair or push that history blindly. Current verification after the Phase 3 increment: `npm run check` passes (66 suites / 202 tests), and `npm run build:verify` exported both Android and iOS bundles with Hermes bytecode. Installed-device validation remains open.

See [`PHASE_1_IMPLEMENTATION_PLAN.md`](PHASE_1_IMPLEMENTATION_PLAN.md) for the per-operation full-integration sequence and [`PHASE_1_TO_3_BACKEND_BLOCKER_REPORT.md`](PHASE_1_TO_3_BACKEND_BLOCKER_REPORT.md) for the backend handoff and release-verification gates.

### Scope

#### Authentication and account

- Login and logout.
- Session restoration and token refresh.
- Signed-in profile and organization.
- Effective role and permission loading.
- Minimal profile and notification preferences.

#### My work

- My Tasks list with filters for active, waiting, review, changes requested, and completed work.
- Task detail screen.
- Task priority, schedule, acceptance criteria, definition of done, and dependencies.
- Start eligible work.
- Clear display of blocked dependencies and unauthorized actions.
- Work I am Leading when the user is an actual task lead.
- Resolve the effective Task Lead using the server contract: `assigned_to` takes precedence, with `recommendation_lead_id` used only when no assignee exists. A role label or unpersisted AI suggestion never grants authority.

#### Subtasks and evidence

- My Subtasks list.
- Subtask detail and execution prerequisites.
- Only the effective Task Lead may create, assign, reorder, reschedule, delete, or change execution rules for subtasks; assigned contributors retain progress and evidence actions.
- Progress updates.
- Evidence selection through the native document or image picker.
- Upload to the existing private Supabase storage paths.
- Submission history and reviewer feedback.

#### Review lifecycle

- Submit a task for review.
- Display the resolved primary or backup reviewer.
- Leader review inbox for authorized users.
- Approve or request changes with feedback.
- Preserve immutable submission versions and prior evidence.
- Refresh affected queries and screens after mutations.

#### Communication

- In-app notification list and unread state.
- Notification navigation to the relevant task or review.
- Announcements.
- Task discussion/comments.
- Foreground Realtime updates.

#### Supporting screens

- Deadlines.
- Task history.
- Read-only project overview for related work.

### Exit criteria

- An employee can complete the full flow from assigned task to evidence-backed submission.
- A Team Leader can review an eligible submission and return or approve it.
- A user cannot review their own submission.
- Dependency, assignment, RLS, and lifecycle errors are shown accurately.
- Failed database transactions do not leave orphaned evidence uploads.
- Realtime changes from the web client appear in the mobile client while it is active.

## Phase 2 — Department leadership and operational AI

### Goal

Add Department Head workflows without reproducing desktop-heavy administration screens.

### Active testing boundary — September 2, 2026

Phase 2 is **not complete**. A safe P2.1/P2.3 project read slice is available for testing, and the first guarded P2-FI project-management vertical slice is implemented locally:

- An authenticated user with `navigation.projects` can open the Projects tab, search and filter a 25-row paged project list, and open a validated UUID detail route.
- Project reads use the configured Supabase client and remain subject to deployed RLS. Missing, deleted, and RLS-hidden details share one unavailable state and do not reveal record existence.
- The mobile mapper uses the canonical statuses `planning`, `active`, `on_hold`, `completed`, and `archived`. The known legacy read value `in_progress` maps to `active`; unknown statuses or priorities fail closed.
- The mobile client now has a self-owned project-create form, server-read closeout readiness panel, and complete/archive RPC adapters. They are controlled by `EXPO_PUBLIC_PHASE_2_LIVE_CAPABILITIES` and default off: `projectCreate`, `projectComplete`, and `projectArchive` must each pass recorded allowed/denied non-production probes before they can be enabled.
- Project editing, member/milestone changes, rollups, activity, Realtime, task creation/assignment, workload, reports, and AI recommendations remain disabled or unimplemented pending the contracts in `docs/PHASE_2_CONTRACTS.md`.

There is no authorization bypass. `navigation.projects` only controls presentation; RLS remains the read boundary. Phase 2 operational controls additionally fail closed for Super Admin and Assistant Head until their exact server scope is verified. The read slice fetches only project summary fields and does not query evidence paths, private notes, personnel data, report content, or AI context. Project completion redacts finance details and directs users to resolve financial clearance on the web.

### Scope

#### Department operations

- Department overview with live operational metrics.
- Mobile task board implemented as virtualized lists and filters rather than a desktop Kanban clone.
- Task creation through the existing atomic RPC.
- Task assignment, team membership, Team Lead, and reviewer configuration.
- Deadline and dependency management.
- Department review inbox.
- Work I am Leading.
- Team workload and attention overview.

#### Projects

- Project list and search.
- Project detail, milestones, members, work rollup, and activity timeline.
- Basic project creation and editing through existing atomic contracts.
- Read-only project health and delivery summaries.

#### Reports

- Permission-scoped department report lists.
- Filters and task drill-down.
- Read-only management summaries.
- Defer complex PDF and CSV generation until native file sharing is designed.

#### AI team recommendations

- Submit a typed recommendation request to the FastAPI gateway.
- Keep employee manager notes and private scoring context on the server.
- Display queue position, processing state, result, and failure state.
- Require human confirmation before applying any recommendation.
- Persist the AI job ID so an interrupted screen can resume checking its status.

### Required backend hardening

- Prefer typed AI business endpoints over arbitrary client-built prompts.
- Enforce model allowlists, role authorization, payload limits, rate limits, and audit events.
- Never return raw private manager notes to mobile.
- Preserve a deterministic fallback only where the product contract allows it.

### Exit criteria

- A Department Head can create, assign, supervise, and review normal department work.
- Mobile and web use the same RPCs and produce equivalent lifecycle results.
- AI recommendations never directly mutate operational assignments.
- An AI outage does not block non-AI task and project work.

## Phase 3 — Advanced workflows

### Goal

Add lower-frequency or technically complex features after the core mobile workflows are stable.

### Active testing boundary — September 3, 2026

Phase 3 is **not complete**. The [full integration plan](PHASE_3_IMPLEMENTATION_PLAN.md) now covers canonical notifications/push, standing organization/task chat, typed management briefs, and server-processed proposal import with saved drafts and explicit atomic commit.

- The existing authenticated Inbox has recipient-filtered pagination, minimal mapping, unknown-type redaction, and guarded task/project destinations. These reads remain subject to Supabase RLS.
- Phase 1 already added mark-one/mark-all read adapters, mark-one UI, and recipient-scoped notification Realtime invalidation behind `notificationWrites` and `phase1Realtime`. Mark-all UI, unread totals/filters, visible mutation errors, and canonical recipient re-fetch on every open remain planned. The current unconditional read-only banner also needs to reflect enabled capabilities accurately.
- Native push registration/delivery, live standing chat, live management briefs, and proposal PDF import remain unimplemented. P3-FI-1 now includes recipient-scoped All/Unread filtering, guarded unread counts, mark-all feedback without downloading changed IDs, and canonical recipient re-fetch before opening a destination. P3-FI-3 has an opt-in development-only synthetic chat preview under More, while P3-FI-5 has shared job-state/backoff and safe identifier persistence; neither connects to a live Phase 3 endpoint.
- Web `main` was rechecked at `042e1a5b240cf667eb3dfa69d263897686de2a04`. Chat base DDL is present, but broad channel/member source policies need reconciliation and live validation. Typed brief/PDF processing and trusted push contracts were not found in the inspected source.
- Proposal draft/approval/commit APIs exist, but the current publication path requires task funding decisions and can create financial records. Mobile draft/source/review work can continue; final commit requires a supported non-financial server contract before full integration can be claimed. Budget and petty cash remain deferred beyond the capstone sequence.

Development, live integration, and release acceptance are tracked separately in [Phase 3 contracts](docs/PHASE_3_CONTRACTS.md). A missing contract blocks only its live operation. Existing Phase 1/2 device and permission checks remain regression/release requirements for the workflows that depend on them; they do not stop independent Phase 3 code. Fixture behavior is visibly development-only, production-rejected, and cannot be reported as live-tested. This implementation ran no migrations or live Phase 3 probes.

### Candidate scope

#### Push notifications

- Request notification permission at an appropriate moment.
- Register Expo push tokens per user and device.
- Add a trusted server or function that sends push notifications.
- Deep-link notifications into the authorized mobile destination.
- Keep Supabase Realtime for active-app updates; do not treat it as background push delivery.

#### Chat

- Standing organization and task channels.
- Message history, sending, editing, reactions, and unread state.
- Attachment handling.
- Defer audio/video calling until a separate native WebRTC evaluation is complete.

#### AI management briefs

- Reuse the authenticated queued-job model.
- Send only permission-scoped report rows.
- Clearly separate verified observations from AI recommendations.

#### Proposal import and decomposition

- Select and upload a PDF from the mobile device.
- Extract PDF text on the server rather than using browser `pdfjs-dist` code.
- Run queued AI decomposition on the existing AI host or a compatible hosted provider.
- Validate and repair the returned hierarchy on the server or in shared pure logic.
- Present an editable draft.
- Keep budget, funding, and petty-cash fields non-operational or unresolved; Phase 3 must not create financial records through proposal import.
- Require explicit review before an atomic database commit.

#### Other candidates

- Work-template library.
- Productivity and performance views.
- Interdepartment collaboration and governance.
- Native report export and sharing.

### Exit criteria

- Each advanced feature has confirmed mobile value and a production-backed web contract.
- Sensitive actions preserve the same authorization, audit, and approval requirements as the web client.
- Large or long-running operations survive navigation and app suspension safely.

## Capstone completion sequence — Phases 4–9

The user requested that the next implementation phases start at Phase 4 on September 6, 2026. These phases finish existing Phase 0–3 gaps without resetting their status or expanding supported roles. Earlier acceptance criteria remain open until evidence satisfies them. Follow the detailed [implementation plan](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md) for slices, source references, tests, and checklists.

For the first web-assisted defense, implement **4 → 5 → 7 → 8** with work prepared on web. Include Phase 6 before Phase 7 when demonstrating creation-to-completion entirely on mobile. Phase 9 is optional unless required by the rubric. Begin live allowed/denied checks in Phase 4 and continue in each phase; verification is not postponed until Phase 8.

## Phase 4 — Evidence review, feedback, and resubmission

- Status: P4.1–P4.4 implemented September 8, 2026; P4.5 live and device acceptance remains open.
- Goal: complete the normal online employee → Task Lead → Head review loop using the existing submission/decision adapters.
- Scope: completion notes and attempt-specific evidence in review screens; authorized native file opening; feedback/progress/submission history; correction and resubmission; pending-decision guards.
- Exit: actual evidence can be inspected, version 1 can be returned and corrected as version 2, eligible reviewers can approve, and forbidden reviewers/file access are denied with recorded tests.
- Plan: [Phase 4 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-4--evidence-review-feedback-and-resubmission).
- Contract notes: [Phase 4 evidence/review contract](docs/PHASE_4_CONTRACTS.md).

## Phase 5 — My work, leading work, deadlines, and project navigation

- Status: P5.1–P5.4 are implemented locally September 15, 2026; deployed RLS and Android/iOS acceptance remain open.
- Goal: make every participant's assigned work easy to find and follow.
- Scope: My Tasks / My Subtasks / Leading views, server-filtered pagination, loaded-item due-soon/overdue navigation with device-local calendar semantics, project-to-task drill-down, and guarded links to details/history.
- Exit: contributors can find directly assigned subtasks, leads can find the work they actually lead, and all supported drill-downs/filters work across pages without exposing unauthorized records. The assignee-only subtask RLS probe and device acceptance remain required before this exit is accepted.
- Plan: [Phase 5 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-5--my-work-leading-work-deadlines-and-project-navigation).
- Contract notes: [Phase 5 work discovery](docs/PHASE_5_CONTRACTS.md).

## Phase 6 — Mobile task planning and delegation

- Status: P6.3 Task-Lead subtask-planning UI/adapters are implemented locally September 17, 2026 behind individual disabled capabilities. P6.1 Department Head task creation and P6.2 participant/reviewer assignment remain unavailable pending a verified permission-scoped people source and atomic plan contract; deployed and device acceptance remain open.
- Goal: create and delegate operational work on mobile.
- Scope: Head task creation, eligible participants/Task Lead/reviewer assignment, and effective-Task-Lead subtask creation/assignment/scheduling/execution rules through verified server contracts.
- Exit: a newly created mobile work plan enters the Phase 4 flow with correct relationships, atomic effects, and allowed/denied management checks. Project creation alone does not satisfy this phase.
- Plan: [Phase 6 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-6--mobile-task-planning-and-delegation).
- Contract notes: [Phase 6 planning/delegation](docs/PHASE_6_CONTRACTS.md).

## Phase 7 — Workflow correctness, synchronization, and recovery

- Status: planned.
- Goal: preserve accurate workflow behavior through stale data, interruptions, and actions from another client.
- Scope: authoritative readiness and useful blockers, submission-ID reconciliation, cleanup safety, focus/reconnect refresh, scoped Realtime, review pagination, canonical notification destinations, and access-change handling.
- Exit: the selected flow recovers after lost responses/restarts/reconnects, does not duplicate submissions or delete finalized evidence, and synchronizes between authorized clients with no offline replay of sensitive actions.
- Plan: [Phase 7 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-7--workflow-correctness-synchronization-and-recovery).

## Phase 8 — Native presentation and mock-defense acceptance

- Status: planned; core mock-defense milestone.
- Goal: present and rehearse the verified operational loop on the actual demonstration build/device.
- Scope: actionable Home, accurate capability messages, integrated evidence UI, accessibility/keyboard/safe-area/file/session checks, test records, and a documented repeatable defense script.
- Exit: the employee → Task Lead → Head cycle, notifications, session restoration, recovery, and a denied operation pass rehearsal with recorded backend/device results. State any web setup and untested-platform limitations explicitly.
- Plan: [Phase 8 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-8--native-presentation-and-mock-defense-acceptance).

## Phase 9 — One AI-assisted capstone extension

- Status: planned; optional unless the rubric requires it.
- Goal: demonstrate one real, permission-scoped AI operation after the core flow is dependable.
- Scope: a confirmed typed recommendation or brief operation, existing job persistence/backoff, result review, explicit human confirmation, and outage recovery. Any assignment application depends on the verified Phase 6 mutation contract.
- Exit: an actual authorized result is demonstrated on mobile, resumes after interruption, cannot act autonomously, and leaves ordinary work usable during an AI outage. A web AI demo or shared helper alone does not complete this mobile phase.
- Plan: [Phase 9 details](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md#phase-9--one-ai-assisted-capstone-extension).

## Deferred beyond the capstone sequence — budget and petty cash

Budget and petty-cash workflows remain outside Phase 3 and Phases 4–9. They have no assigned implementation phase. This replaces the earlier “Phase 4 or later” placeholder; Phase 4 now covers evidence review and resubmission. The current financial implementation and its deployed contract still need a stable-contract audit and an explicit product decision.

A future separately approved plan may include:

- Department budget overview.
- Task and subtask allocations.
- Contextual task/subtask cash requests against a selected approved budget line, with optional Task Lead subtask caps.
- Correction, resubmission, reviewer notification, release acknowledgement, and reservation-expiry states.
- Receipt uploads and liquidation review.
- Immutable ledger and funding-state visibility.

Any future financial mutation must remain online-only, server-authoritative, auditable, and protected by verified RLS/RPC/Storage contracts. None of these items count toward Phase 3 or the Phases 4–9 capstone sequence.

## Deferred mobile scope — recommended 30%

The following features should remain web-first unless the capstone requirements explicitly demand them on mobile:

- Super Admin database backup and restore-grade exports.
- Migration and database maintenance tools.
- Full organization-tree construction and complex permission administration.
- Hard-coded Executive, Legislative, HRMO, and Finance demonstration dashboards until they use live backend data.
- Full desktop Kanban, hierarchy, timeline, and drag-and-drop experiences.
- Browser-equivalent rich-text editing.
- Browser-side PDF parsing and print-window report generation.
- Audio and video calls.
- Large audit, ledger, and data-health administration workspaces.
- Full interdepartment governance authoring on a phone-sized screen.

Deferred does not mean permanently rejected. Each item should be reconsidered when it has a live backend contract, a clear mobile user journey, and an acceptable native interaction design.

## AI deployment expectations

The mobile app will not run DeepSeek or Ollama locally. It will call the existing eFlow gateway with the signed-in user's Supabase access token.

```text
Expo mobile app
  -> Supabase Auth, RPC, Storage, and Realtime
  -> published Cloudflare endpoint
  -> eFlow FastAPI gateway on port 8322
  -> private AI API on port 8321
  -> Ollama / DeepSeek on the team AI host
```

For a capstone demonstration, the rotating Quick Tunnel may be acceptable. For a dependable deployment, replace it with a named Cloudflare Tunnel or a stable hosted gateway. The AI host must be running for AI features to work, but normal Supabase-backed workflows should remain available during an AI outage.

## Web-to-mobile update workflow

When the web repository changes:

1. Record the new `main` commit SHA.
2. Compare it against the previous baseline SHA.
3. Review changed files in this priority order:
   1. Supabase migrations, RLS policies, RPCs, and storage rules.
   2. FastAPI routes, authentication, and request/response payloads.
   3. Roles, permissions, and navigation access rules.
   4. Task, project, subtask, review, budget, and governance lifecycles.
   5. Shared types, pure selectors, validators, and mappers.
   6. AI contracts and queue behavior.
   7. UI-only changes.
4. Update the mobile parity matrix.
5. Implement only relevant contract or approved design changes.
6. Run contract, type, unit, and affected end-to-end tests.
7. Replace the recorded baseline SHA only after mobile compatibility is verified.

Do not automatically copy every web push. Backend and security changes may require immediate mobile work, while unfinished desktop layouts or mock-data screens usually do not.

## Definition of done for every mobile feature

A feature is complete only when:

- The user journey and supported roles are documented.
- The app checks effective permissions before presenting actions.
- Supabase RLS, RPCs, or the gateway remain the final authorization boundary.
- Loading, empty, offline, retry, validation, and server-error states are handled.
- Long lists are virtualized.
- Forms handle the mobile keyboard and safe areas.
- File uploads have size/type validation and cleanup behavior.
- Realtime subscriptions are cleaned up correctly.
- Sensitive data is not logged or stored insecurely.
- Unit or contract tests cover important pure logic and payloads.
- The workflow is tested against the same deployed backend used by the web client.
- The feature works on both Android and iOS, or any platform limitation is explicitly documented.

## Recommended first implementation slice

After Phase 0, implement this vertical workflow first:

```text
Login
  -> My Tasks
  -> Task Detail
  -> My Subtask
  -> Add Progress and Evidence
  -> Submit for Review
  -> Reviewer Requests Changes or Approves
  -> Employee Sees Updated Status and Feedback
```

This slice validates authentication, permissions, Supabase queries, RPCs, storage uploads, Realtime updates, navigation, and error handling without depending on the unfinished desktop redesign.
