# eFlow Mobile Implementation Phases

## Roadmap status

- Status: In progress
- Mobile stack: Expo, React Native, and TypeScript
- Web upstream: [Rivaly-Kun/eFlow-e-Governance-Project](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project)
- Web audit baseline: [`508aabc8881630b37a62a973645ecb0bb386e99e`](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/commit/508aabc8881630b37a62a973645ecb0bb386e99e)
- Latest upstream `main` inspected: `042e1a5b240cf667eb3dfa69d263897686de2a04`; this is not yet the adopted mobile baseline
- Baseline date: August 27, 2026

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

There is deliberately no authorization bypass. Development fixtures, if added, must be explicit and development-only; exact non-production identities are preferred for integration work. Each live Storage/RPC/read/write capability remains disabled until its own allowed/denied probe passes. Do not disable RLS, use a service-role key, make the bucket public, or report fixture-backed behavior as live integration. The earlier linked Supabase CLI migration list was empty; this remains an auditability problem, not proof that the deployed schema is missing, and the mobile repository must not repair or push that history blindly. `npm run check` passes (52 suites / 161 tests). The standard `npm run build:verify` still fails in this Windows environment while spawning Hermes bytecode (`spawn UNKNOWN`); no-bytecode Android and iOS exports with one worker succeeded, so Hermes bytecode/native-device verification remains open.

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

### Active testing boundary — August 30, 2026

Phase 2 is **not complete**. A safe P2.1/P2.3 project read slice is available for testing:

- An authenticated user with `navigation.projects` can open the Projects tab, search and filter a 25-row paged project list, and open a validated UUID detail route.
- Project reads use the configured Supabase client and remain subject to deployed RLS. Missing, deleted, and RLS-hidden details share one unavailable state and do not reveal record existence.
- The mobile mapper uses the canonical statuses `planning`, `active`, `on_hold`, `completed`, and `archived`. The known legacy read value `in_progress` maps to `active`; unknown statuses or priorities fail closed.
- Project creation/editing, members, milestones, rollups, activity, Realtime, task assignment, workload, reports, and AI recommendations remain disabled or unimplemented pending the contracts in `docs/PHASE_2_CONTRACTS.md`.

There is no authorization bypass. `navigation.projects` only controls presentation; RLS remains the read boundary. The slice fetches only project summary fields and does not query evidence paths, private notes, personnel data, report content, or AI context.

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

### Active testing boundary — August 30, 2026

Phase 3 is **not complete**. A safe P3.0/P3.2 notification read slice is available for testing:

- An authenticated, resolved profile can open the Inbox tab, refresh a paged notification list, and see only rows requested for the current profile ID and returned by Supabase RLS.
- The query selects a minimal inbox projection; it does not select financial-record metadata. Supported task/project notifications may open only the existing permission-gated UUID detail routes, which perform a fresh RLS-backed read.
- Unknown notification types, including finance-related types, render as a generic unavailable mobile notification without source title, message, actor, reason, linked record ID, or destination.
- Phase 1 now contains capability-gated recipient-owned mark-one and mark-all adapters, but both default disabled until recipient-only live probes pass. Unread counts, mark-all UI, notification Realtime invalidation, push permission/token registration/delivery, chat, AI briefs, proposal import, and all other Phase 3 mutations remain disabled or unimplemented.

There is no notification or authorization bypass. The explicit `user_id` client filter narrows the request but is not a security boundary; recipient-only RLS reads/updates, Realtime delivery, and allowed/denied identity probes must be verified before the Inbox can be considered a completed workflow. See [`docs/PHASE_3_CONTRACTS.md`](docs/PHASE_3_CONTRACTS.md).

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

## Deferred to Phase 4 or later — budget and petty cash

Budget and petty-cash workflows are explicitly excluded from Phase 3. The current web implementation and its deployed schema, RLS, RPC, Storage, lifecycle, and role behavior are not considered stable enough to serve as the authoritative mobile contract.

Reconsider this scope only after a future upstream audit confirms a stable, production-backed financial workflow. A future Phase 4 or later plan may include:

- Department budget overview.
- Task and subtask allocations.
- Contextual task/subtask cash requests against a selected approved budget line, with optional Task Lead subtask caps.
- Correction, resubmission, reviewer notification, release acknowledgement, and reservation-expiry states.
- Receipt uploads and liquidation review.
- Immutable ledger and funding-state visibility.

Any future financial mutation must remain online-only, server-authoritative, auditable, and protected by verified RLS/RPC/Storage contracts. None of these items count toward Phase 3 scope or completion.

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
