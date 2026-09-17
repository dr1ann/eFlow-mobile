# Mock capstone defense: mobile flow readiness

Assessed September 6, 2026. This is a source-based readiness assessment and recommended demo scope, not a declaration that deployed integration or device acceptance has passed.

Execution follow-up: the user requested phases starting at Phase 4. See the [Phases 4–9 implementation plan](../PHASE_4_TO_9_IMPLEMENTATION_PLAN.md) for the delivery order, tests, and exit criteria. The old finance phase placeholder is replaced by an unnumbered deferral beyond this capstone sequence.

- Mobile commit inspected: `71a2a9b98f00b0484ba6de237f0b5f6c643bb53a` (`main`; clean before this documentation update).
- Web repository inspected through GitHub: [GabrielCahiyang/eFlow-e-Governance-Project](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project).
- Current web `main`: [`042e1a5b240cf667eb3dfa69d263897686de2a04`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/commit/042e1a5b240cf667eb3dfa69d263897686de2a04), eight commits ahead of the recorded mobile baseline `508aabc8881630b37a62a973645ecb0bb386e99e`.
- The current web SHA is the same SHA already inspected by the newer mobile Phase 1–3 plans. This check found no newer `main` push.
- The adopted compatibility baseline remains `508aabc`; this assessment does not replace deployed acceptance.

## Recommendation

Finish the existing employee-to-reviewer loop first. The app already contains its RPC, upload, and decision plumbing, but important user-facing steps are missing. The strongest bounded defense demonstrates real assignment, progress, evidence inspection, requested changes, resubmission, approval, and synchronized results.

For the fastest complete system demonstration, prepare the project, task, team, and subtasks through the web app and perform execution and review on mobile. If the required demonstration must begin entirely on mobile, add task creation/assignment and Task Lead subtask management before calling that mobile journey complete. This recommendation does not change the long-term roadmap or settle the final 70/30 scope.

## Current implementation, checked against source

| Area | What exists | What remains |
| --- | --- | --- |
| Foundation | Supabase sign-in, secure session adapter, access/profile resolution, protected routes, query layer, gateway client, and tests | Installed-device session/refresh/deep-link acceptance and real allowed/denied identities |
| My work | Paged My Tasks, status filters, task/subtask details, start/resume action | Dedicated My Subtasks and Work I am Leading UI; deadline view; useful dependency explanations |
| Progress and submission | Online-only progress form, native picker, rules RPC, private uploads, task/subtask submit adapters, sequential cleanup claim/remove | User-facing validation/retry polish, recovery by submission UUID after an uncertain response, and actual Storage/RPC acceptance |
| Reviews | Inbox and task/subtask approve/request-changes forms; self-review and stored-reviewer guards | Submission note/evidence display and opening, prior attempts, feedback history, reliable refresh and inbox pagination |
| Notifications | Recipient-filtered Inbox, All/Unread filters, mark-one/mark-all feedback, canonical recipient re-fetch on open, guarded task/project destinations, notification Realtime | Verified cross-user event delivery; direct subtask/review destinations if adopted; native push remains separate |
| Communication | Recipient announcements and task text discussion adapters/screens | Audience/participant and two-client acceptance |
| Projects and planning | Paged list/search/filter/detail; self-owned create form; readiness, complete, archive adapters; guarded effective-Task-Lead subtask planning | Department Head task creation/assignment, permission-scoped people/reviewer selection, deployed management probes, members/rollups/activity, and broader editing |
| Advanced features | Development-only synthetic chat UI; shared AI job states/backoff and safe ID persistence | Live chat, mobile staffing recommendations, reports/briefs, push, server PDF processing, and mobile proposal import |

Source anchors: [task screens](../src/features/tasks/screens), [subtask screens](../src/features/subtasks/screens), [review screens](../src/features/reviews/screens), [notification screen](../src/features/notifications/screens/notification-list-screen.tsx), [project screens](../src/features/projects/screens), [evidence storage adapter](../src/features/subtasks/evidence-storage.ts).

### Configuration is ahead of the old status prose

The local configuration currently enables all 13 recognized Phase 1 capabilities and the Phase 2 `projectCreate`, `projectComplete`, and `projectArchive` capabilities. Phase 3 development fixtures are enabled; no Phase 3 live capability list is set. Defaults in source and the example environment remain off.

Consequently, “all workflow mutations are disabled” and “evidence is only a local preview” are stale descriptions of the implemented/local configuration. Enabled flags are presentation controls; they do not establish that the allowed/denied backend tests passed. No deployment receipts or live acceptance were established by this assessment. Local environment files and credentials are not included in this report.

## Work to finish in priority order

### 1. Complete the evidence review and rework loop

**Required for the core mobile demonstration.**

The Phase 4 code slice now renders completion notes, author/timestamp/version/status, attempt-scoped attachment metadata, and task/subtask feedback history. It signs a private file only when the reviewer opens it, hands the fresh URL to the native system handler, redacts open failures, and never persists the URL. Subtask progress history, requested-change resubmission labels, blank-note pre-upload validation, and locked pending decision controls are also implemented.

The remaining work is live and device acceptance: open the agreed defense file types on Android and iOS, use real contributor/Task Lead/reviewer/unrelated identities, and record allowed/denied Storage and RPC outcomes. Parent-task rework follows the verified server sequence: Resume work changes `changes_requested` to `in_progress`, then submit the corrected parent attempt.

Relevant source: [task review](../src/features/reviews/screens/task-review-screen.tsx), [subtask review](../src/features/reviews/screens/subtask-review-screen.tsx), [subtask detail](../src/features/subtasks/screens/subtask-detail-screen.tsx), [subtask query helpers](../src/features/subtasks/query-options.ts), [task query helpers](../src/features/tasks/query-options.ts).

Acceptance: the reviewer opens the actual uploaded file, requests a specific correction, the employee sees that feedback, submits version 2, and both parties can distinguish the two attempts after approval.

### 2. Prove the existing live workflow with real demo identities

**Required integration/rehearsal work, not a request to rebuild the existing adapters.**

Use the agreed non-production backend and real relationships: assigned contributor, effective Task Lead, routed Department Head reviewer, and an unrelated account. The Task Lead must come from the persisted assignment relationship, not a separate invented role or a display label.

Verify task start, progress, evidence rules/upload/signed access, subtask submission/decision, parent submission/decision, and notifications. Include wrong-reviewer, self-review, unauthorized-file, duplicate-submission, and inactive-account denial checks. Confirm the evidence migration and private bucket settings from deployed definitions without blindly reapplying migrations.

The older reports list remaining acceptance checks; they are not evidence that every operation currently fails. Record actual outcomes before claiming the demonstration is integrated.

### 3. Make each person's work discoverable

**High priority for a smooth mobile demonstration.**

The data helpers for `listMySubtasks` and `listLeadingTasks` exist, but the Work screen uses only the My Tasks feed. Add My Tasks / My Subtasks / Leading views, with actionable status and due-date filters. A contributor should be able to find an assigned subtask directly, including a valid assignment that is not represented in the parent task's team-member filter.

Connect project detail to its authorized linked tasks, and task detail back to the project. Project detail currently provides a summary and lifecycle controls without a work list. Add a small due-soon/overdue view using authorized data; a full department dashboard is unnecessary for the first rehearsal.

### 4. Add mobile planning only if the demo includes mobile work creation

**Required for a self-contained mobile creation-to-completion journey; web setup can cover this for the first system demo.**

Add a bounded Department Head task form and assignment flow: title, description, project, due date, priority, acceptance criteria, Task Lead, contributors, and primary/backup reviewer. The upstream uses `create_task_with_details` and `assign_task_with_details`; validate their exact scope and side effects before adopting them.

The guarded effective-Task-Lead subtask-planning route now supports create, assignment, schedule/order, and execution-mode controls through individual disabled capabilities, using only already-visible task-team data. Contributors retain progress/evidence actions. It remains a local integration slice until the source policies/RPCs pass deployed allowed/denied probes; it does not provide a Department Head task-create or people-selection flow. See [Phase 6 contract notes](PHASE_6_CONTRACTS.md).

For the first slice, prioritize creating/assigning a small work plan. Broader project editing, member/milestone administration, advanced dependencies, workload analysis, and reports can follow independently.

### 5. Finish lifecycle explanations, refresh, and uncertain-result recovery

**Required where these states affect the chosen demonstration.**

- Resolve dependency/prerequisite readiness and show a useful reason before offering an impossible action. Task detail currently displays a dependency count, while subtask screens do not explain execution prerequisites.
- Treat loading or failed subtask reads as unknown readiness. The current parent-submission UI passes an empty array when subtask data is unavailable; the readiness helper treats an empty array as ready. The database remains authoritative, but the UI can offer submission prematurely.
- Add useful, redacted messages for known backend lifecycle failures. Generic errors currently conceal many server rejection reasons.
- Retain a safe submission-attempt identifier and reconcile it after a lost response before offering another upload. The upload helpers preserve evidence on ambiguous failures, but generate IDs inside each call and do not provide a restart/reconciliation flow.
- Add screen-focus refresh or appropriate scoped subscriptions for My Work, the review inbox, and task/subtask review/detail screens. Existing task-detail and notification subscriptions do not prove every mounted destination stays current.
- Wire the review inbox's next-page controls: it uses infinite queries, but currently has no load-more or end-reached action. Add visible partial-load failures and stable/deduplicated ordering.
- Review notification routing: current destinations open tasks/projects. Add exact subtask/review navigation only with a canonical backend destination and a fresh access check.

A cross-client test must show mobile submission reaching the correct web/mobile reviewer and the decision returning to the employee without requiring a full app restart.

### 6. Replace development presentation and rehearse on a phone

**Required demo polish after the functional loop works.**

- Replace the current diagnostic Home content with the person's next actions: assigned work, due items, awaiting review, and Inbox shortcuts. Keep gateway/profile diagnostics in Settings or a development surface.
- Remove obsolete unconditional copy, including the My Work “upload and submission are disabled” banner and Home's “Tasks and reviews begin in Phase 1.” Make any capability-unavailable state accurate.
- Integrate the standalone “Evidence picker test” into the actual evidence/submission journey so selected files do not appear to carry over when they do not.
- Show names, statuses, dates, and clear success/error feedback. A permission count or backend/RPC terminology should not be the main user-facing explanation.
- Validate keyboard reachability, file URI handling, signed-file opening, safe areas, readable text, touch targets, and long lists on Android and iOS, or document the platform not demonstrated.
- Rehearse sign-out/account switching, restart/session restoration, brief connectivity loss, and refresh recovery on the actual demonstration build/device.

## Upstream compatibility findings

The [baseline comparison](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/508aabc8881630b37a62a973645ecb0bb386e99e...042e1a5b240cf667eb3dfa69d263897686de2a04) includes three added migrations. Source tree comparisons were used as well as the compare endpoint because the large generated-runtime removal truncates the compare file list.

| Change | Mobile consequence |
| --- | --- |
| `20260831000001_task_evidence_security.sql` | Private task evidence, server rules, immutable bindings, actual-assignee precedence, claim-before-remove cleanup. Mobile already implements much of this; finish the reader/recovery UX and verify deployment/allowed-denied behavior. |
| `20260831000003_project_completion_lifecycle.sql` | Server readiness/complete/archive operations. Mobile already has guarded adapters and financial-blocker redaction; verify actual lifecycle behavior before presenting closeout as accepted. |
| `20260831000002_cash_release_schedule_override.sql` and cash-clearance UI | Financial workflows remain deferred beyond the capstone sequence. Existing server financial guards can still block task/project completion; use a genuinely non-financial example or resolve legitimate financial clearance on web. Do not bypass the guard. |
| Project workspace, role-label, and web shell changes | Preserve canonical roles/contracts; the desktop visual redesign does not need literal mobile replication. |

The Python gateway router source files are unchanged from the recorded baseline; generated cache files account for the router-directory difference. An authenticated generic queued AI proxy exists, but it is not by itself a completed typed mobile staffing/brief operation.

The current web [task submission helper](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/src/app/features/tasks/services/taskReviewLifecycleService.ts) and [subtask workflow helper](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/src/app/features/subtasks/services/subtaskWorkflowService.ts) still perform direct removal after upload failures. The [backend handoff](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/docs/mobile-phase-1-backend-handoff.md) requires cleanup claims first and a trusted abandoned-upload worker. These are backend/web follow-ups; they do not mean the mobile claim/remove helper is missing.

## AI and deferred scope for the defense

If the panel requires the AI differentiator, demonstrate one real, scoped AI operation after the operational flow is dependable. It can remain on the web for the first system demonstration. A mobile recommendation would still need its business endpoint, authorized context, queue/result UI, restart recovery, human confirmation, and useful offline/unavailable state. Shared job utilities and a successful gateway health check are not evidence of a working mobile AI feature.

Keep live chat, native background push, mobile proposal PDF import, extensive reports, calls, and desktop administration outside the minimum mobile rehearsal unless the rubric specifically requires one. Task comments and an in-app Inbox already cover basic foreground communication. The current development chat preview is synthetic and must not be presented as live messaging.

Budget/petty cash remains deferred beyond the capstone sequence with no assigned implementation phase. The proposal publication path's funding coupling remains a reason to require a supported non-financial contract before implementing final mobile proposal commit.

## Suggested defense script

1. A Department Head prepares one project and a simple non-financial task with a real Task Lead, contributors, and reviewer routing on web; use mobile creation only after the P6.1/P6.2 atomic contract and people-source probes are accepted.
2. The Task Lead starts the task and assigns two small subtasks through the available verified interface; the guarded mobile planning route can be used only after its individual Phase 6 capability probes are accepted.
3. An employee opens assigned work on mobile, records progress, selects real evidence, and submits subtask version 1.
4. The Task Lead opens the evidence on mobile and requests a specific correction.
5. The employee sees the feedback/history, uploads corrected evidence, and submits version 2. The Task Lead approves; all required subtasks become approved.
6. The Task Lead submits the parent task. The routed Department Head inspects it and approves.
7. The employee sees completion and the notification; the web shows the same canonical state. Show project closeout only when its verified readiness rules permit it.
8. Show session restoration and one denied self/unrelated-user operation. Demonstrate AI separately if required, with its actual availability stated.

Seed demonstration records through authorized workflows in the agreed test environment. Do not fabricate live success or weaken authorization to make the script run.

## Validation and next tests

Commands run during this assessment:

- `npm run check` — passed lint, TypeScript, and all 66 Jest suites / 202 tests.
- `npm run build:verify` — passed Android and iOS exports with Hermes bytecode. This verifies bundling, not an installed native application or device interaction.
- Source/manual inspection — mobile routes, screen behavior, API/query wiring, capability configuration, upstream commits/tree hashes, workflow helpers, gateway routes, and migration inventory.

Tests added/updated: none. Tests: not applicable to the documentation changes; repository tests were run to assess the existing baseline.

Not run: live Supabase/Storage/RLS/RPC mutations, two-client Realtime acceptance, a live AI job, and installed Android/iOS interaction tests. This assessment did not establish an agreed non-production identity/record set or perform device interaction. No backend mutation, migration, app source change, or baseline adoption was performed.

For the implementation follow-up, add behavioral tests alongside the affected screens, particularly `task-review-screen.test.tsx`, `subtask-review-screen.test.tsx`, `task-submit-screen.test.tsx`, `subtask-submit-screen.test.tsx`, `subtask-progress-screen.test.tsx`, and `review-inbox-screen.test.tsx`. Those screen test files are currently absent. Extend detail/query/storage and submission-lifecycle tests for feedback history, missing readiness data, expired file links, pagination, pending decisions, offline rejection, and lost-response recovery. Add controlled end-to-end workflow coverage; passing helper tests alone does not prove the user can complete the review loop.
