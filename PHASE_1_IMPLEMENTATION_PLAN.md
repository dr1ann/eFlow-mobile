# Phase 1 Implementation Plan — Employee and Team Leader MVP

## Plan status

- Status: P1.1 is implemented. P1.2/P1.3 now have a guarded read-only Work/task/subtask test slice, and P1.4 has a local-only evidence-picker preview. Phase 1 is not complete.
- Current repository phase: Phase 0 foundation plus a partial Phase 1 read path; deployed-policy, workflow mutation, Realtime, identity, and device acceptance remain open
- Mobile repository baseline: `3270a2c` (`feat(phase-0): establish secure mobile foundation`)
- Mobile stack: Expo SDK 57, React Native, TypeScript, Expo Router, Supabase, and TanStack Query
- Native project mode: managed/CNG; no committed `ios/` or `android/` directories
- Source roadmap: `MOBILE_IMPLEMENTATION_PHASES.md`
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected: `7b072123a20876940be84217dbb6af3ad8d2700f` (not yet adopted as the mobile baseline)
- Plan created: August 26, 2026

The August 27 migration archive contains 61 files: the prior 57 files are content-identical after newline normalization, and the four new files have Git blob hashes identical to GitHub `main`. The Phase 1 compatibility change is implemented and tested; the budget additions remain Phase 3.

The current safe test boundary does not bypass backend authorization. It exposes RLS-backed task/subtask reads and local picker behavior only. Evidence is not uploaded or persisted, and all sensitive workflow mutations stay unavailable until the backend handoff in `PHASE_1_BLOCKER_REPORT.md` is satisfied.

## Outcome

Phase 1 will deliver the first production-backed mobile product workflow:

```text
Employee signs in
  -> opens My Tasks or My Subtasks
  -> understands priority, schedule, requirements, and dependencies
  -> starts eligible work
  -> records subtask progress
  -> selects and validates private evidence
  -> submits a versioned subtask attempt
  -> resolved reviewer requests changes or approves
  -> employee sees feedback and resubmits when needed
  -> every subtask becomes approved
  -> effective Task Lead submits the parent task
  -> resolved primary or backup reviewer requests changes or approves
  -> employee sees the final status, history, and notification
```

The supporting mobile experience will include assigned and leading work, deadlines, read-only related-project context, notifications, announcements, narrow task discussion, and foreground Realtime refresh.

Phase 1 is complete only when the workflow uses the same deployed RLS, RPC, private-storage, and lifecycle contracts as the web application. Mock task or review data does not count.

## Planning decisions and scope boundaries

1. **Finish Phase 0 acceptance first.** Phase 1 feature code must not hide missing generated database types, unverified RLS, or incomplete session/device testing.
2. **Treat Team Leader as a work relationship, not an invented mobile role.** The effective Task Lead follows the deployed precedence `assigned_to ?? recommendation_lead_id`. The persisted recommendation is only a fallback when no assignee exists; an unpersisted AI suggestion or a role label cannot grant lead or review authority.
3. **Use record-level reviewer routing.** Review actions require the current user to be the resolved primary reviewer, backup reviewer, or another explicitly authorized server-side reviewer, and the user must not be the submitter. Client checks only control presentation.
4. **Preserve the two review levels.** Delegated subtasks complete through their own evidence and review lifecycle before the parent task can enter task review.
5. **Make all Phase 1 mutations online-only.** Starting work, progress updates, evidence uploads, submissions, decisions, read-state changes, and comments are never queued for automatic replay. Safe reads may show in-memory cached data with a stale/offline indicator.
6. **Keep evidence private.** Use the verified private `task-attachments` bucket and unique object paths. Never produce or persist public evidence URLs; create short-lived signed URLs only after an authorized read.
7. **Do not copy browser file handling.** Native picker assets are normalized to a mobile upload object; browser `File`, drag-and-drop, and DOM APIs are not reused.
8. **Use TanStack Query as the server-state owner.** Feature code uses typed query options, scoped keys, invalidation, cancellation, and mutation state. Do not add a general global store or a second feature cache.
9. **Use Realtime as an invalidation signal.** Foreground database events invalidate or patch well-defined query keys and are deduplicated. They are not background push notifications.
10. **Keep communication narrow.** Phase 1 task discussion is text-only and task-scoped. General channels, attachments, reactions, editing, and calls remain Phase 3 chat work.
11. **Keep notifications in-app.** Expo push registration and delivery remain Phase 3. Phase 1 supports database-backed notification reads, unread state, and authorized navigation while the app is active.
12. **Keep project access read-only.** A related project overview may show title, schedule, milestones, members, and rollup fields already allowed by RLS. Project creation and editing remain Phase 2.
13. **Keep Department Head operations out of Phase 1.** A user may open a specific review only when the deployed routing contract authorizes it, but department dashboards, task creation, assignment management, and broad department review operations remain Phase 2.
14. **Use mobile-native navigation and controls.** Keep Native Tabs with nested stacks, virtualize long lists with `FlatList`, use native stack titles and safe-area behavior, and prefer SDK-compatible `@expo/ui` controls for short menus, pickers, and grouped forms.

## Upstream drift assessment

The recorded compatibility work through [`508aabc`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/ddca4ae45ba9fe8e897a9570b2e7b93e8c986cb9...508aabc8881630b37a62a973645ecb0bb386e99e) remains the mobile baseline. Current web `main` is [`7b072123`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/508aabc8881630b37a62a973645ecb0bb386e99e...7b072123a20876940be84217dbb6af3ad8d2700f), seven commits ahead. The initial comparison found no added Supabase migrations; Phase 1-adjacent login, role, task-detail/status, review-inbox, and project-query changes still require compatibility classification before the baseline moves.

| Classification | Observed change | Phase 1 response |
| --- | --- | --- |
| Required compatibility | Parent-task submission UI now checks that every subtask is approved; the server migration already guards the same transition. | Add one tested submission-readiness selector for UX, then rely on the RPC/trigger as authority. A subtask at 100% or `for_review` is not approved until it is `completed`. |
| Required compatibility | `20260826000002_task_leader_only_subtask_management.sql` makes `coalesce(assigned_to, recommendation_lead_id)` the effective Task Lead and sole subtask-structure manager. | Map the fallback field, apply assigned-first precedence in selectors and list queries, and test that a stale recommendation cannot override an assignee. |
| Required verification | Review readiness, reviewer routing, evidence Storage, and live RLS remain deployment-sensitive. | Reconfirm allowed and denied behavior with the Phase 1 test identities before enabling workflow screens and mutations. |
| Pending compatibility review | Web `main` advanced from `508aabc` to `7b072123` without new migration files in the inspected comparison. | Keep `508aabc` as the recorded baseline until Phase 1-adjacent application contract changes are classified and verified. |
| Out of scope | Three new migrations add dynamic task funding, cash correction/resubmission, financial attachments, and reviewer notifications. | Keep implementation in Phase 3. Phase 1 preserves unknown notifications safely and may still navigate an authorized task reference without exposing financial actions. |
| Web-only | Desktop review panels, drawers, Kanban, and browser file controls changed. | Reimplement the behavior through native routes, lists, forms, and pickers. |

The mobile compatibility layer now matches the generated schema and current source contract. Live deployment acceptance remains separate and must still pass before Phase 1 screens or mutations are considered complete.

## Phase 0 readiness gate

The following must be true before the first Phase 1 feature pull request is considered complete:

- [x] Existing workspace changes are preserved and the Phase 0 quality command passed before the P1.1 foundation work.
- [x] Android and iOS native exports build from the current route/configuration foundation.
- [x] `src/contracts/database.types.ts` is regenerated from the selected non-production Supabase project; the current Phase 0 bootstrap projection is not extended by hand.
- [x] The supplied August 27 archive contains the 61 migrations on GitHub `main` at `508aabc`; all existing files and all four new Git blobs match. The linked non-production project still returned an empty CLI migration list on August 26, 2026; establish an auditable deployment record, but do not run a destructive migration repair or schema push from mobile.
- [ ] Active employee and reviewer test accounts can sign in, restore sessions, refresh tokens, and sign out.
- [ ] Missing, inactive, malformed, and unsupported-role accounts fail closed.
- [ ] One authenticated Supabase read and gateway health request succeed against the shared test environment.
- [ ] Direct deep links cannot bypass the existing protected-route and permission guards.
- [ ] Android and iOS device checks cover cold session restore, sign-out cleanup, light/dark mode, enlarged text, and keyboard behavior.
- [x] Upstream through `508aabc` is classified from GitHub, the supplied migrations, and the generated schema. Deployed RLS, RPC, storage, and Realtime behavior still needs identity-based probes.

If a gate is blocked, keep Phase 0 open and record the missing credential, test account, backend owner, migration, or device path. Do not replace it with mock data.

## Contract inventory to verify

Create `docs/PHASE_1_CONTRACTS.md` during P1.0 and record exact generated types, columns, RPC signatures, permissions, RLS behavior, storage policies, and Realtime publication state. The current upstream indicates these likely contracts, but deployed reality remains authoritative.

| Capability | Candidate authoritative contract to verify |
| --- | --- |
| Tasks and leading work | `tasks`; effective Task Lead is `assigned_to` or, only when it is null, `recommendation_lead_id`; task team arrays/relations; dependency IDs; soft-delete/archive fields |
| Task lifecycle | `transition_task_status`, `submit_task_for_review`, `decide_task_review` |
| Task submissions | `task_submissions`, `task_attachments`; immutable version and decision fields |
| Subtasks | `subtasks`; assigned contributor IDs, status, progress, reviewer, due date, and ordering fields |
| Subtask progress | `save_subtask_progress`, `subtask_progress_updates` |
| Subtask submissions | `submit_subtask_for_review`, `decide_subtask_review`, `subtask_submissions`, `subtask_submission_attachments` |
| History | Task status/activity tables or RPC-backed views used by the deployed web contract |
| Evidence | Private `task-attachments` bucket, upload/delete policies, task and subtask path conventions, signed-read policy |
| Notifications | `notifications`; recipient-scoped read/update policy; Realtime publication |
| Announcements | `announcements`, `announcement_recipients`; published/expiry visibility and recipient read state |
| Discussion | The minimum task-scoped channel/message contract and participant RLS needed for text comments |
| Projects | RLS-scoped read contract for the project linked by a task |
| Authorization | Effective navigation/action permissions plus per-record assignment and reviewer checks |

The contract audit must also verify that clients cannot send arbitrary email or notifications. Workflow RPCs should create authorized notifications atomically. Mobile must not copy a broad client-controlled email request or recipient fan-out path.

## Target navigation

Routes remain thin adapters under `src/app/`; screens, hooks, query options, mappers, and components stay in feature directories.

```text
src/app/
  (auth)/
  (rejected)/
  (protected)/
    _layout.tsx
    (tabs)/
      _layout.tsx             Native tabs after access bootstrap
      work/
        _layout.tsx           Native stack
        index.tsx             My Tasks / My Subtasks / Leading Work entry
      reviews/
        _layout.tsx           Native stack
        index.tsx             Assigned review inbox
      inbox/
        _layout.tsx           Native stack
        index.tsx             Notifications and announcements entry
      settings/
        _layout.tsx
        index.tsx
    tasks/
      [id].tsx                Shared authorized task detail
      [id]/submit.tsx         Evidence-backed task submission
    subtasks/
      [id].tsx                Shared authorized subtask detail
      [id]/progress.tsx       Progress form
      [id]/submit.tsx         Evidence-backed subtask submission
    reviews/
      tasks/[id].tsx          Task review detail and decision
      subtasks/[id].tsx       Subtask review detail and decision
    announcements/[id].tsx
    projects/[id].tsx         Read-only related-project overview
```

The tab set is derived only after the authenticated access snapshot is loaded. Permission changes received through Realtime intentionally revoke/remount forbidden navigation. Every detail route performs a fresh authorized read; a URL parameter is never treated as proof of access.

## Target module boundaries

```text
src/
  components/
    empty-state.tsx
    error-state.tsx
    list-state.tsx
    offline-notice.tsx
  contracts/
    database.types.ts         Generated only
    announcements.ts
    notifications.ts
    reviews.ts
    subtasks.ts
    tasks.ts
  features/
    tasks/
      api/
      components/
      hooks/
      screens/
      mappers.ts
      query-options.ts
      selectors.ts
    subtasks/
      api/
      components/
      hooks/
      screens/
      evidence.ts
      query-options.ts
    reviews/
      api/
      components/
      hooks/
      screens/
      eligibility.ts
      query-options.ts
    notifications/
    announcements/
    discussions/
    projects/
    settings/
  lib/
    query/
      keys.ts
    supabase/
      errors.ts
      realtime.ts
      storage.ts
```

Do not create every directory in advance. Add each feature boundary with the first vertical slice that uses it.

## Query, mutation, and Realtime model

Feature query keys must include the current user and organization where the result can differ by session. Candidate factories are:

```text
tasks.list(userId, filter, page)
tasks.leading(userId, page)
tasks.detail(taskId)
tasks.history(taskId, page)
subtasks.mine(userId, filter, page)
subtasks.byTask(taskId)
subtasks.detail(subtaskId)
subtasks.progress(subtaskId, page)
subtasks.submissions(subtaskId, page)
reviews.inbox(userId, kind, page)
reviews.taskSubmission(taskId)
notifications.list(userId, page)
notifications.unread(userId)
announcements.list(userId, filter, page)
projects.detail(projectId)
discussions.task(taskId, page)
```

Rules:

- Use paged/virtualized reads for tasks, subtasks, histories, notifications, announcements, and comments.
- Pass React Query cancellation signals into cancellable reads where the Supabase client supports them.
- Keep cached reads in memory only. When offline, show cached data as stale and pause new reads; do not persist private query results across app restarts in Phase 1.
- Set every mutation to online-only with no automatic retry. Duplicate taps are disabled while pending.
- Invalidate the smallest correct set after success: the changed detail, relevant lists, review inbox, submission/history queries, unread counts, and related project rollup when applicable.
- Realtime callbacks validate event IDs, deduplicate repeated events, and invalidate keys rather than maintaining an unbounded parallel cache.
- Unsubscribe on unmount, sign-out, user change, and access revocation. Reconnect causes one bounded refresh.
- Normalize PostgREST/RPC/storage failures into typed, non-sensitive user messages for offline, unauthorized, forbidden, missing, stale/invalid lifecycle, dependency blocked, duplicate, validation, timeout, and server failure states.

## Work packages

### P1.0 — Phase 0 acceptance and Phase 1 contract freeze

Purpose: prevent task screens from being built against hand-written or stale contracts.

Implementation:

- Complete the Phase 0 readiness gate above.
- Compare upstream `508aabc` with the previous inspected/audited commits in the repository-prescribed order.
- Audit the selected upstream migration source and regenerate database types. Record the missing CLI migration history as a deployment-observability issue; do not infer that the deployed schema is empty and do not repair it from the mobile repository.
- Record exact Phase 1 tables, functions, storage paths, RLS policies, Realtime publications, permission keys, and error contracts in `docs/PHASE_1_CONTRACTS.md`.
- Prepare test identities for:
  - assigned employee/contributor;
  - effective Task Lead;
  - primary reviewer;
  - backup reviewer;
  - unauthorized employee;
  - self-review collision;
  - inactive/missing profile.
- Confirm whether task-level review can be completed by the Phase 1 personas. If deployed routing requires a Department Head-only action, record the narrow route requirement or obtain a product decision before implementation.
- Define evidence MIME allowlist, maximum per-file size, maximum files per submission, signed-URL lifetime, and cleanup owner from deployed policy rather than client guesses.
- Decide the minimum task-discussion contract that is production-backed without importing Phase 3 chat features.

Acceptance:

- Generated types compile without hand additions.
- Every mutation and sensitive read has an identified server-side authorization boundary.
- One allowed and one denied test identity are documented for each review tier and private-storage operation.
- Upstream drift is classified, but the baseline SHA is updated only after compatibility verification.

Tests and verification:

- Run `npm run check` after generated type or executable contract changes.
- Run `npm run build:verify` after dependency, route, or Expo configuration changes.
- Run non-production integration probes for RLS, RPC signatures, storage upload/delete/signed read, and Realtime publication.

### P1.1 — Domain contracts, selectors, and feature data foundation

Purpose: establish deterministic mobile models before building screens.

Implementation:

- Add runtime-validated task, subtask, submission, review, notification, announcement, comment, and related-project mappers over generated database rows.
- Add one pure task-state model for `pending_assignment`, `todo`, `in_progress`, `for_review`, `changes_requested`, `completed`, and `cancelled`.
- Add pure selectors for:
  - My Tasks membership;
  - My Subtasks membership;
  - effective Task Lead and Work I am Leading;
  - active, waiting, review, changes-requested, completed, and history filters;
  - dependency completion/blockers;
  - deadline grouping and stable sorting;
  - reviewer display and record-level eligibility;
  - parent-task submission readiness, where all subtasks must be `completed`;
  - immutable submission-version presentation.
- Confirm the exact `waiting` filter contract. The candidate mapping is pending assignment or unresolved dependency blockers; do not freeze it until it matches the approved product behavior.
- Extend query-key factories with user/organization scoping and add feature query options.
- Add typed Supabase/RPC/storage error mapping without exposing raw SQL, tokens, private paths, or server internals.
- Install native dependencies only with `npx expo install`. The expected Phase 1 set is `expo-document-picker`, `expo-image-picker`, and `@expo/ui`; add `expo-file-system` only if the SDK 57 upload spike proves it is required.
- Prove one native picker asset can be converted to the byte representation accepted by Supabase Storage on both platforms before building the full upload UI.

Acceptance:

- No screen consumes raw Supabase rows.
- Unknown or malformed status/notification rows fail safely.
- Lead and reviewer UI never grants authority from a role label alone.
- Filters and submission readiness are deterministic and covered exhaustively.

Expected tests:

- `src/features/tasks/mappers.test.ts`
- `src/features/tasks/selectors.test.ts`
- `src/features/tasks/submission-readiness.test.ts`
- `src/features/subtasks/mappers.test.ts`
- `src/features/reviews/eligibility.test.ts`
- `src/features/notifications/navigation.test.ts`
- `src/lib/supabase/errors.test.ts`

### P1.2 — Native shell, account completion, and protected feature routing

Purpose: turn the Phase 0 shell into the stable navigation surface for Phase 1.

Current status (August 29, 2026): partially implemented. The permission-gated Work tab and guarded task/subtask UUID routes exist. Home is intentionally retained for the Phase 0 gateway diagnostic; Reviews, Inbox, badges, account completion, and their routes remain open.

Implementation:

- Replace the placeholder Home tab with the Work stack and add Reviews and Inbox stacks while retaining Settings.
- Keep no more than four native tabs: Work, Reviews, Inbox, and Settings.
- Use native stack headers and titles. Long lists use `FlatList` with automatic content insets; short settings/form groups may use `@expo/ui` inside `Host`.
- Add guarded shared routes for task, subtask, review, announcement, and project details.
- Add authorization-aware deep-link resolution:
  - validate UUID parameters;
  - perform a fresh RLS-scoped fetch;
  - confirm assignment/reviewer eligibility where needed;
  - show not found or access denied without leaking whether a forbidden record exists.
- Complete the minimal account screen with profile identity, organization, canonical role, effective permissions summary, and verified notification preference fields.
- Add an online-only notification-preference update for the signed-in profile, using the confirmed own-profile RLS/RPC contract. Invalidate the profile query after success and restore the server value after rejection; never let a user update another profile through an arbitrary ID.
- Preserve sign-out cleanup for query cache, endpoint cache, Realtime subscriptions, picker/upload state, and pending navigation intents.
- Add an Inbox unread badge only from the authenticated unread query; do not infer it from stale local counts.

Acceptance:

- Signed-out, rejected, and unauthorized deep links cannot render protected cached data.
- Back navigation returns to the originating stack without duplicate screens.
- Access changes revoke hidden/forbidden routes promptly.
- Navigation works with enlarged text, screen readers, safe areas, and the Android keyboard.

Expected tests:

- Route-policy tests for every new protected route.
- Component tests for allowed, denied, deleted, malformed, loading, offline, and error destinations.
- Sign-out tests proving Phase 1 queries and navigation intents are removed.
- Notification-preference tests for own-profile success, another-user denial, offline state, pending/disabled state, server rejection, and cache refresh.

### P1.3 — My Tasks, My Subtasks, leading work, deadlines, and read-only detail

Purpose: deliver the complete read path before enabling mutations.

Current status (August 29, 2026): partially implemented. Work provides a virtualized, paged, filterable task feed with refresh/loading/empty/error/offline presentation plus task and subtask detail reads. A separate My Subtasks list, leading-work view, deadlines, history, signed evidence access, related-project detail, and live allowed/denied RLS acceptance remain open.

Implementation:

- Build a virtualized My Tasks list with the approved filters, stable IDs, pagination, pull-to-refresh, empty states, stale/offline state, and due/priority/status accessibility labels.
- Build My Subtasks as an assignment-scoped virtualized list with parent task, reviewer, status, progress, due date, and blocker summary.
- Add Work I am Leading using the verified live Task Lead field; a recommendation field may be shown only as legacy context and never enables actions.
- Build task detail with:
  - description, priority, status, schedule, deadline, and tags;
  - acceptance criteria and definition of done;
  - dependency list with completed/blocked state;
  - team and resolved reviewer summary;
  - subtasks and submission-readiness summary;
  - submission history, feedback, and task history;
  - link to the read-only related-project overview.
- Build subtask detail with execution prerequisites, progress history, immutable submission attempts, evidence metadata, reviewer feedback, and signed evidence open/download actions.
- Add a deadlines view derived from the same task/subtask query data and deterministic date selectors.
- Treat RLS-returned empty results, deleted records, and forbidden records as distinct UI outcomes where the contract permits them to be distinguished safely.

Acceptance:

- An employee sees only work returned by authorized contracts.
- Lists remain usable with realistically large data sets and duplicate Realtime events.
- A Task Lead sees leading work only from verified assignment data.
- Task and subtask details render every roadmap field or document a confirmed unavailable contract.

Expected tests:

- Query mapping, pagination boundaries, deduplication, filter/sort rules, and cache keys.
- Screen loading, empty, cached-offline, refresh, server-error, and permission-denied states.
- Accessibility roles/labels for filters, list rows, evidence links, and retry actions.

### P1.4 — Start work, subtask progress, native evidence, and subtask submission

Purpose: complete the employee execution half of the first vertical slice.

Current status (August 29, 2026): only the safe local picker preview is implemented. Assigned contributors can choose a document or image and inspect normalized metadata; the app does not persist the local URI, upload a file, call an RPC, or present selection as a submission. All P1.4 mutations remain blocked on the verified Storage/RLS contract.

Implementation:

- Add an online-only Start/Resume action that calls the verified lifecycle RPC and never directly writes task status.
- Show dependency, assignment, stale-state, and unauthorized blockers before the action; always surface the authoritative server rejection if state changed.
- Build a keyboard-safe progress form for percent complete, blocker category/details, next step, note, and optional progress attachment according to the verified RPC.
- Build native evidence selection:
  - document picker and image-library picker;
  - lazy media-library permission request;
  - cancellation as a normal non-error outcome;
  - MIME/extension validation, exact size boundaries, duplicate detection, count limit, and sanitized display name;
  - platform URI normalization without logging local paths or file contents.
- Upload sequentially or with a small bounded concurrency limit to verified private paths, with progress and cancellation state.
- For a subtask submission, create a client submission UUID, upload evidence under its unique prefix, then call `submit_subtask_for_review` once with note and attachment metadata.
- If upload fails, remove successfully uploaded objects. If the RPC fails, remove every object from that attempt before presenting failure.
- Add a backend reconciliation requirement if delete permissions or network loss cannot guarantee cleanup: unreferenced temporary objects need an authenticated finalize/cleanup contract or scheduled age-based sweeper before Phase 1 exit.
- Invalidate subtask, parent task, lists, progress, submissions, review inbox, history, and notification queries after success.

Acceptance:

- An assigned contributor can start eligible work, record progress, and create an evidence-backed immutable subtask submission.
- A cancelled picker creates no object or database row.
- Invalid or oversized files are rejected before upload.
- A failed database operation has no referenced or untracked evidence left behind after cleanup/reconciliation.
- Duplicate taps and offline submissions cannot create duplicate attempts.

Expected tests:

- File allowlist, size boundary, count, duplicate, sanitized-name, path, picker cancellation, and platform URI tests.
- RPC payload and metadata mapper tests.
- Upload failure at each file position and RPC-failure cleanup tests.
- Start/progress/submission tests for success, offline, stale state, dependency block, unauthorized user, duplicate press, and server rejection.

### P1.5 — Subtask reviewer inbox and decision lifecycle

Purpose: close the delegated-work review loop before parent task submission.

Implementation:

- Build a virtualized pending-subtask review inbox scoped by the server-returned reviewer identity.
- Show parent task/project context, contributor, version, note, evidence, prior attempts, progress/blockers, and reviewer identity.
- Generate signed evidence URLs only on user action and expire them from memory after their short lifetime.
- Require explicit confirmation for approval and non-empty feedback for changes requested.
- Call `decide_subtask_review` online with no automatic retry.
- Re-read or invalidate all affected records after decision so stale local state cannot show a false success.
- Reject self-review, non-reviewer access, already-decided attempts, deleted work, malformed deep links, and stale/duplicate decisions.
- On requested changes, keep earlier attempt/evidence immutable and return the subtask to the server-defined rework state.

Acceptance:

- The resolved reviewer can approve or request changes on one pending subtask attempt.
- The submitter and unrelated users cannot open or decide the review.
- Prior versions and evidence remain unchanged after resubmission.
- The parent task cannot become review-ready until every subtask is completed by this lifecycle.

Expected tests:

- Primary success and changes-requested paths.
- Self-review, wrong reviewer, stale attempt, duplicate decision, empty feedback, offline, RLS denial, and server-error paths.
- Cache invalidation and Realtime deduplication after a decision.

### P1.6 — Parent task submission and resolved reviewer decision

Purpose: complete the end-to-end employee-to-reviewer workflow.

Implementation:

- Show parent submission readiness from live subtasks. A subtask at 100% or awaiting review remains incomplete until its status is `completed`.
- Recheck readiness and resolved reviewer immediately before any evidence upload.
- Require the verified parent-task note/evidence rules; do not invent a stricter or weaker client rule than the deployed RPC.
- Use a unique submission ID and verified private task path, call `submit_task_for_review` once, and apply the same cleanup/reconciliation policy as subtask evidence.
- Display the resolved primary and backup reviewers without implying that both can always act simultaneously; follow the server routing contract.
- Build the task-review inbox/detail for records the current user can actually decide.
- Require feedback for changes requested, prevent self-review, and call `decide_task_review` online without automatic retry.
- Preserve immutable task submission versions, attachment associations, decision feedback, audit metadata visible to the user, and prior attempts.
- Refresh task detail/list, review inbox, submissions, history, notifications, deadlines, and related-project rollups after success.

Acceptance:

- The effective Task Lead can submit a review-ready task.
- The resolved eligible reviewer can request changes or approve.
- Self-review, unfinished subtasks, blocked dependencies, wrong reviewer, stale status, duplicate submission, and duplicate decision are rejected accurately.
- Approval changes the task to the server-defined completed state and remains visible after restart/reload.

Expected tests:

- Submission-readiness matrix and dependency blockers.
- Parent upload/RPC cleanup and immutable versioning.
- Primary reviewer, backup reviewer, self-review, unauthorized role, stale state, duplicate action, offline, and server rejection.
- Exact query invalidation and user-visible final state.

### P1.7 — Notifications, announcements, task discussion, and foreground Realtime

Purpose: make the workflow discoverable and responsive without adding Phase 3 push or general chat.

Implementation:

- Build a paged notification list, unread count, mark-one-read, and mark-all-read using recipient-scoped contracts.
- Map only Phase 1 notification kinds to stable native destinations. Preserve unknown kinds as readable notifications with no unsafe destination.
- Before navigating from a notification, validate the destination ID and perform an authorized read. Deleted, malformed, or forbidden targets show a safe message.
- Build the published announcement list/detail with unread/read state, expiry handling, search/filter, and recipient-scoped marking.
- Do not let the mobile client publish announcements or materialize arbitrary recipients in Phase 1.
- Implement text-only task discussion if P1.0 confirms a participant-authorized production contract:
  - paged messages;
  - bounded message length;
  - sender identity from `auth.uid()`;
  - send-once behavior with no offline queue;
  - foreground Realtime updates and cleanup.
- Do not implement reactions, editing, attachments, standing channels, arbitrary mentions, audio, video, or calls.
- Subscribe only to Phase 1 tables confirmed in the Realtime publication and invalidate the corresponding query keys.

Acceptance:

- A workflow notification opens the correct authorized task, subtask, or review.
- Unread state survives restart because it is server-backed.
- Announcements respect published, audience, expiry, and recipient read contracts.
- Web-side task/review/notification/announcement/comment changes appear while mobile is active.
- Sign-out and unmount leave no Phase 1 Realtime channels active.

Expected tests:

- Notification mapping, unread counts, deduplication, mark read/all, malformed/deleted/forbidden destinations, and sign-out cleanup.
- Announcement audience, expiry, read state, empty, search/filter, and Realtime tests.
- Comment validation, sender spoofing prevention, unauthorized task access, duplicate send, offline, pagination, and subscription cleanup.

### P1.8 — Integrated hardening, deployed validation, and sign-off

Purpose: prove Phase 1 as one workflow rather than disconnected screens.

Implementation:

- Run the complete employee -> subtask review -> parent task review journey against the shared non-production backend with dedicated identities.
- Exercise primary and backup reviewer routing and prove self-review denial at both review levels.
- Exercise web-to-mobile and mobile-to-web Realtime changes while the app is active.
- Test airplane mode, reconnect, background/foreground, process restart, token refresh, sign-out/user switch, stale deep link, interrupted upload, and cleanup recovery.
- Scan tracked source, generated bundles/source maps, logs, screenshots, and test fixtures for tokens, service-role keys, private file URLs, private paths, personnel content, and test credentials.
- Validate realistic list sizes, accessibility, enlarged text, contrast, touch targets, keyboard behavior, safe areas, and picker/file URI behavior on Android and iOS.
- Update the roadmap status, baseline record, feature parity matrix, README, and contract notes with verified reality.

Acceptance:

- Every Phase 1 roadmap exit criterion has automated or documented manual evidence.
- `npm run check` and `npm run build:verify` pass from a clean install after final executable changes.
- Non-production RLS/RPC/storage tests include at least one allowed and denied identity.
- No unresolved high-severity authorization, self-review, evidence-cleanup, immutable-history, session-leak, or secret-leak issue remains.

## Test matrix

| Area | Automated evidence | Deployed/manual evidence |
| --- | --- | --- |
| Contracts | Generated types, runtime mappers, malformed rows | Migration/RPC inventory matches selected non-production project |
| Task filters | Every status, dependency waiting, sort/pagination boundaries | Representative assigned/leading tasks under RLS |
| Task detail | Loading, empty, deleted, forbidden, offline, error | Real acceptance criteria, dependencies, history, and project link |
| Subtasks | Assignment, prerequisites, deadlines, progress mapping | Assigned contributor and unrelated user |
| Evidence | MIME/size/name/path/cancel/cleanup/signed URL | Android and iOS document/image URI upload and open |
| Subtask submit | Payload, duplicate, stale, offline, cleanup | Versioned attempt and server-generated notifications |
| Subtask review | Approve/change, self-review, wrong reviewer, immutable prior version | Resolved reviewer and denied identities |
| Parent readiness | Zero, incomplete, awaiting-review, and completed subtasks | Database trigger/RPC rejects unfinished subtasks |
| Task submit/review | Primary/backup, self-review, dependency, duplicate, atomic state | Full task completion and changes-requested/resubmit loop |
| Query cache | Scoped keys, invalidation, offline/stale state, user switch | No previous-user data after sign-out |
| Realtime | Mapping, duplicate event, reconnect, cleanup | Web change appears in active mobile app |
| Notifications | Mapping, unread, dedupe, safe destinations | Authorized, forbidden, deleted, and malformed targets |
| Announcements | Audience, expiry, read state, search/filter | Published announcement appears and marks read |
| Discussion | Validation, pagination, unauthorized send/read, cleanup | Text comment synchronizes web/mobile |
| Accessibility | Labels, roles, disabled/loading state, error recovery | Screen reader, enlarged text, contrast, touch targets |
| Lifecycle | AppState, cancellation, restart, stale session | Background/foreground, reconnect, interrupted upload |
| Privacy | Redaction, signed/private links, no sensitive logs | Bundle/log/source-map and screenshot scan |

Automated tests must use injected clients, controlled fakes, or mocks. They must not connect to production Supabase, production Storage, the live gateway, or the AI host.

## Manual Android and iOS checklist

- [ ] Cold sign-in, session restore, token refresh, sign-out, and user switch.
- [ ] My Tasks and My Subtasks with empty, small, and realistic large data sets.
- [ ] Filters, pull-to-refresh, pagination, deadline display, and stale/offline indicator.
- [ ] Authorized and unauthorized direct links to task, subtask, review, announcement, and project routes.
- [ ] Document picker cancellation, accepted/rejected document types, and maximum-size boundary.
- [ ] Image-library permission denial/retry and accepted/rejected image evidence.
- [ ] Upload interruption, RPC failure cleanup, reconnect, and submission retry.
- [ ] Keyboard-safe progress, submission, review-feedback, and comment forms.
- [ ] Subtask changes-requested/resubmission and approval.
- [ ] Parent submission blocked until every subtask is approved.
- [ ] Primary and backup task review; self-review remains denied.
- [ ] Web-to-mobile foreground Realtime update and subscription cleanup after leaving the screen.
- [ ] Notification navigation for valid, forbidden, deleted, and malformed destinations.
- [ ] Announcement expiry and read state.
- [ ] Light/dark appearance, enlarged text, screen reader labels, contrast, safe areas, and 44/48-point touch targets.

## Phase 1 exit checklist

- [ ] Phase 0 readiness gate is complete.
- [ ] Phase 1 deployed contracts and upstream compatibility are documented.
- [x] Generated database types cover all currently identified Phase 1 tables and RPCs.
- [ ] Employee can browse assigned tasks and subtasks, including blocked dependencies and deadlines.
- [ ] Actual Task Lead can browse leading work without role-label escalation.
- [ ] Employee can start eligible work and save progress.
- [ ] Employee can select, validate, upload, and submit private evidence.
- [ ] Failed submissions leave no orphaned evidence after cleanup/reconciliation.
- [ ] Subtask reviewer can request changes or approve; submitter and unrelated users cannot review.
- [ ] Parent task remains blocked until every subtask is approved.
- [ ] Actual Task Lead can submit a review-ready parent task.
- [ ] Resolved primary or backup reviewer can request changes or approve; self-review is denied.
- [ ] Submission versions, evidence associations, prior feedback, and history are immutable.
- [ ] Notifications and announcements have server-backed unread/read state and safe navigation.
- [ ] Task discussion is task-scoped, text-only, and server-authorized. If that live contract is missing, Phase 1 remains open with an explicit backend blocker.
- [ ] Foreground web changes appear on mobile and every subscription cleans up.
- [ ] Loading, empty, offline, timeout, retry, stale, forbidden, and server-error states are usable.
- [ ] Long lists are virtualized and accessible.
- [ ] `npm run check` and `npm run build:verify` pass after final implementation.
- [ ] Android and iOS manual results are recorded, including any approved limitation.

## Suggested implementation sequence and review boundaries

Keep the first delivery vertical and reviewable:

1. Phase 0 sign-off, upstream/deployed contract audit, generated types, and test identities.
2. Domain mappers/selectors/query keys plus native routes and read-only task/subtask screens.
3. Start work, subtask progress, native evidence upload, and subtask submission.
4. Subtask reviewer inbox, changes requested, approval, and parent-readiness gate.
5. Parent task submission, primary/backup review, changes requested, approval, and immutable history.
6. Notifications, announcements, narrow task discussion, and foreground Realtime integration.
7. Cross-platform, non-production, accessibility, privacy, failure-recovery, and sign-off pass.

Each boundary includes its tests and ends with `npm run check`. Boundaries that add routes, Expo packages, native configuration, or file-picker integration also run `npm run build:verify`.

## Main risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Phase 0 looks implemented but is not deployed/device accepted | Keep a hard readiness gate; do not hide it with Phase 1 screens. |
| Bootstrap database types encourage guessed feature rows | Regenerate from the selected non-production project before writing feature code. |
| Upstream moves beyond the recorded audit | Classify the new commit, compare migration blobs, verify generated/deployed contracts, and update the baseline only after compatibility. |
| Team Leader is confused with a canonical authorization role | Derive leading work from live assignment and review rights from server routing; deny by default. |
| Task-level reviewer routing does not fit Phase 1 personas | Confirm test accounts and routing in P1.0; obtain a product decision before expanding Department Head scope. |
| Web code performs broad client-side notification/email actions | Use workflow RPC-generated notifications; do not expose arbitrary recipient or email payloads from mobile. |
| Storage and database cannot be one transaction | Use unique temporary paths, compensating deletion, verified delete policy, and backend orphan reconciliation where needed. |
| Signed evidence URLs leak or outlive access | Generate on demand, use short expiry, keep only in memory, and reauthorize every open. |
| Offline mutation replay creates duplicate or stale workflow transitions | Set Phase 1 mutations online-only, no automatic retries, and disable duplicate taps. |
| Realtime and pagination create duplicate or missing rows | Treat events as typed invalidation signals, deduplicate by stable ID, and refresh once on reconnect. |
| General chat scope leaks into Phase 1 | Limit discussion to task-scoped text; defer reactions, editing, attachments, channels, and calls. |
| Windows development hides iOS picker/URI problems | Require a physical iOS or approved remote/macOS device path before sign-off. |
| Final visual direction changes | Keep business contracts, query options, and selectors independent from presentation components. |
