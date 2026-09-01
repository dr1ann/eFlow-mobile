# Phase 1 Full Integration Implementation Plan

## Plan status

- Status: ready for implementation; Phase 1 remains incomplete until live integration and device acceptance pass
- Updated: August 31, 2026
- Mobile repository: Phase 0 foundation plus partial Phase 1 task/subtask reads, partial Phase 2 project reads, and partial Phase 3 notification reads
- Mobile stack: Expo SDK 57, React Native 0.86, TypeScript, Expo Router, Supabase, TanStack Query, and `@expo/ui`
- Native project mode: managed/CNG; no committed `ios/` or `android/` directories
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest web `main` inspected: [`042e1a5b240cf667eb3dfa69d263897686de2a04`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/commit/042e1a5b240cf667eb3dfa69d263897686de2a04); not yet adopted as the mobile baseline
- Shared non-production Supabase project configured by mobile: `ixnfphgjyelhckjwjkdv`
- Evidence migration: `20260831000001_task_evidence_security.sql`
- Evidence migration SHA-256: `38615808bf4cf6c7e6220ad4477d56155d5c25fedc0e2610823a8e4b5b184c4c`

The evidence migration committed by the teammate exactly matches the supplied SQL. The teammate reports that it has already been applied to the shared Supabase project. Do not rerun it merely for this implementation. Regenerate types and verify its deployed functions, policies, bucket configuration, and real-user behavior through read-only inspection and scoped integration probes.

## Implementation decision

Phase 1 development proceeds now. Pending release verification is not a general coding blocker.

Use three separate states:

| State | Meaning | Implementation response |
| --- | --- | --- |
| Development-ready | UI, routes, contracts, mappers, validators, state handling, and tests can be implemented with injected fakes | Build now |
| Live-integration gated | One exact Storage/RPC/read/write operation is not yet accepted against the shared backend | Build the adapter and UI; keep only that live capability disabled |
| Release-verification pending | Code and integration may exist, but allowed/denied, lifecycle, Realtime, failure, and device evidence is incomplete | Continue development; do not claim Phase 1 complete |

Development fakes must be available only when `__DEV__` is true and an explicit development fixture setting is enabled. Fixture-backed screens must show a visible “Development data” notice. Production routes must never silently return mocked success.

Client rollout flags are not authorization. Supabase RLS, RPCs, triggers, and Storage policies remain the security boundary.

## Goal and completion journey

Deliver this live workflow:

```text
Assigned employee signs in
  -> opens assigned task and subtask
  -> starts eligible work
  -> records progress
  -> selects and validates private evidence
  -> uploads evidence to a unique private path
  -> submits an immutable subtask attempt
  -> correctly routed reviewer requests changes or approves
  -> employee sees feedback and resubmits
  -> every subtask becomes approved
  -> effective Task Leader submits the parent task
  -> assigned primary/backup reviewer requests changes or approves
  -> employee and lead see final state, history, and notification
```

Supporting Phase 1 scope:

- Assigned tasks, assigned subtasks, leading work, deadlines, and detail/history.
- Short-lived authorized evidence access.
- Recipient-owned notifications and published announcements.
- Text-only task discussion if its participant RLS contract is confirmed.
- Foreground Realtime invalidation.
- Authentication/session/deep-link/account-switch hardening required by the workflow.

Not in this plan:

- Project creation/editing, department-wide operations, reports, and AI recommendations.
- Push notifications.
- General chat, attachments/reactions/editing, or calls.
- Budget, funding, cash release, petty cash, receipts, or other financial operations.

## Intended permission contract

| Actor | Intended Phase 1 authority |
| --- | --- |
| Assigned employee/contributor | Read assigned work, save progress, upload evidence, and submit assigned work |
| Effective Task Leader | Manage their task's subtasks and submit the parent task; review only when the stored reviewer route selects them |
| Assigned primary/backup reviewer | Decide an eligible pending submission, never their own |
| Authorized Head/Assistant Head | Only the record/organization actions explicitly granted by the deployed contract |
| Ordinary project member | Related-project read only when RLS permits; membership does not grant task management |
| Super Admin | Oversight/read-only for operational work unless a separately approved server contract says otherwise |
| Unrelated, inactive, missing-profile, or anonymous actor | No protected access |

The effective Task Leader is `assigned_to`, falling back to `recommendation_lead_id` only when `assigned_to` is null. A displayed role, navigation permission, or AI recommendation never grants record authority.

## Adopted evidence contract

Subject to deployed verification, mobile will implement the committed migration contract:

### Bucket and paths

| Workflow | Bucket | Object path |
| --- | --- | --- |
| Parent task submission | `task-attachments` | `<task-id>/<submission-id>/<unique-name>` |
| Subtask submission | `task-attachments` | `subtasks/<subtask-id>/<submission-id>/<unique-name>` |
| Subtask progress attachment | `task-attachments` | `subtasks/<subtask-id>/progress/<unique-name>` |

Rules:

- Generate the submission UUID before uploading.
- Use a random UUID prefix plus a sanitized display filename.
- Use `upsert: false`; never overwrite an existing evidence object.
- Store object paths, not public or signed URLs, in RPC payloads.
- Keep picker URIs, file contents, access tokens, and signed URLs out of logs and analytics.

### Server rules

- Read limits from `get_task_evidence_rules()`.
- Current committed limits are nonempty files, at most 50 MiB per file, at most ten files per submission, and at least one file for a subtask submission.
- Use the exact server MIME list; do not relabel arbitrary bytes to bypass it.
- Parent-task evidence remains optional unless the deployed RPC contract changes.
- Use a 300-second signed-read lifetime unless the backend publishes a different approved value.
- Keep signed URLs only in memory and reauthorize every open.

### Upload transport decision

React Native must upload binary `ArrayBuffer` data rather than browser `File`, `Blob`, or `FormData` behavior. The [Supabase React Native upload guidance](https://supabase.com/docs/reference/javascript/storage-from-upload) requires an ArrayBuffer-compatible upload body.

Supabase recommends [resumable TUS uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads) for files larger than 6 MiB or unstable networks. Phase 1 begins with a device spike:

1. Use `expo-document-picker` with cache copying and `expo-image-picker` with original assets.
2. Prove Android and iOS URI-to-ArrayBuffer conversion with `expo/fetch`.
3. Measure memory and cancellation behavior at 1 byte, 6 MiB, 6 MiB + 1 byte, and the 50 MiB server boundary.
4. If standard upload is not acceptable above 6 MiB, validate `tus-js-client` in Expo or obtain an approved lower mobile limit/trusted upload contract.
5. Do not silently impose a lower mobile maximum than the server contract.
6. Add `expo-file-system` or `tus-js-client` only if the spike proves the existing SDK/runtime cannot satisfy the requirement. Submission-attempt UUIDs use the runtime Web Crypto API when available and a non-native UUID fallback so an existing development binary does not require an `expo-crypto` module.

### Cleanup and ambiguous outcomes

For every uploaded but unfinalized object:

1. Call `claim_task_evidence_cleanup(path, 'task-attachments')`.
2. Wait for the claim result.
3. If claimed, remove that exact path through the Storage API.
4. Never claim and remove in parallel or remove first.
5. Retry removal at the same path after a network failure; never reuse a claimed path.

For a timed-out submission:

1. Reconcile by the caller-generated submission UUID.
2. If the attempt exists, preserve its finalized evidence and treat the server state as authoritative.
3. If it does not exist, claim and remove the temporary objects.
4. If reconciliation is still unknown, show a non-success state, refetch, and rely on the trusted orphan worker rather than risking deletion of finalized evidence.

For a timed-out progress RPC, refetch progress by the uploaded path/latest server record before cleanup. A finalized seal must prevent deletion if the request committed.

## Existing implementation to preserve

- Secure Supabase session adapter, auth bootstrap, profile/role/permission resolution, and sign-out cleanup.
- Query lifecycle bound to AppState and network connectivity.
- Typed gateway client and existing Phase 0 diagnostic.
- Permission-gated Native Tabs and protected UUID routes.
- Paged/filterable Work task feed.
- RLS-backed task and subtask detail reads.
- Task/subtask mappers, selectors, submission readiness, and reviewer eligibility.
- Native document/image picker preview and file metadata normalization.
- Recipient-filtered notification list and guarded task/project destinations.
- Read-only project list/detail from later partial phases.
- Existing tests and user changes, including `PHASE_1_TO_3_BACKEND_BLOCKER_REPORT.md`.

Do not remove or regress the partial Phase 2/3 routes while completing Phase 1.

## Target architecture

```text
src/
  contracts/
    database.types.ts                 generated only
    tasks.ts
    subtasks.ts
    reviews.ts
    notifications.ts
    announcements.ts
    discussions.ts
  features/
    tasks/
      api/
      mutations/
      screens/
    subtasks/
      api/
      evidence/
      mutations/
      screens/
    reviews/
      api/
      mutations/
      screens/
    notifications/
      api/
      mutations/
      screens/
    announcements/
      api/
      screens/
    discussions/
      api/
      screens/
  lib/
    phase-1/
      capabilities.ts
      require-online.ts
    query/
      keys.ts
    supabase/
      evidence-storage.ts
      errors.ts
      realtime.ts
  test/
    phase-1-fixtures/
```

Add directories only with the first package that uses them.

### Per-operation rollout capabilities

Define non-authoritative rollout capabilities:

- `taskTransition`
- `subtaskProgress`
- `evidenceRules`
- `evidenceUpload`
- `evidenceSignedRead`
- `subtaskSubmit`
- `subtaskDecision`
- `taskSubmit`
- `taskDecision`
- `notificationWrites`
- `announcementReads`
- `taskComments`
- `phase1Realtime`

Each defaults to disabled for live mutation/read surfaces that have not been accepted. Enable one capability only after recording its exact project, operation, actor relationship, expected result, actual result, and allowed/denied evidence. A capability flag may hide an action but cannot authorize it.

### Mutation safety

- Call a shared `requireOnline()` before creating a sensitive mutation.
- Use `retry: false` for lifecycle, review, cleanup-claim, read-state, and comment mutations.
- Do not persist TanStack MutationCache or automatically resume sensitive mutations.
- Disable duplicate presses while pending.
- Give submissions caller-generated IDs and reconcile ambiguous responses.
- Cancel safe reads on unmount; do not blindly repeat a mutation after timeout.
- Clear queries, mutation state, evidence selections, signed URLs, fixture mode, and Realtime channels on sign-out/account change.

### Native UI and navigation

- Preserve Native Tabs with no more than five visible items on Android: Home, Inbox, conditional Work, conditional Projects, and More.
- Place Reviews, Notices, and Settings behind permission-gated stack destinations opened from More; each review decision screen still performs a fresh RLS-backed read and requires a stored primary/backup route.
- Keep the temporary Home diagnostic until its Phase 0 acceptance function is moved to Settings in a separate navigation decision.
- Use native stack routes for task, subtask, review, announcement, progress, and submission screens.
- Use `FlatList` for tasks, subtasks, reviews, notifications, announcements, histories, and comments.
- Use `@expo/ui` `FieldGroup`, controls, and sheets only for short fixed forms/actions; every native tree is wrapped in `Host`.
- Use keyboard-safe scroll views, automatic content insets, safe areas, accessible labels, disabled/loading states, and selectable error text.
- Add the `expo-image-picker` config plugin with an evidence-specific photo permission and disable unneeded camera/microphone permissions. Run native export verification after the config change.

## Query and invalidation model

Extend the existing query keys without putting tokens, private paths, signed URLs, notes, or evidence names in keys:

```text
tasks.leading(userId, page)
tasks.history(taskId, page)
tasks.submissions(taskId, page)
subtasks.mine(userId, filter, page)
subtasks.progress(subtaskId, page)
subtasks.submissions(subtaskId, page)
reviews.inbox(userId, kind, page)
reviews.taskSubmission(taskId)
reviews.subtaskSubmission(subtaskId)
evidence.rules(environmentId)
notifications.unread(userId)
announcements.list(userId, filter, page)
discussions.task(taskId, page)
```

After a successful mutation, invalidate only the affected detail, list, history, submission, review, notification, deadline, and related-project keys. Realtime events are validated, deduplicated invalidation signals rather than a second server-state store.

## Work packages

### P1-FI.0 — Contract adoption and development harness

Purpose: make the new backend source usable without stopping UI development.

Implementation:

- Update Phase 1 roadmap/contract notes from “no evidence fix exists” to “fix committed and reported deployed; live acceptance pending.”
- Regenerate `src/contracts/database.types.ts` from `ixnfphgjyelhckjwjkdv`; verify the two new evidence RPCs appear without hand editing.
- Record the exact `get_task_evidence_rules` result and new grants/policies/triggers.
- Add strict runtime schemas for rules, evidence metadata, RPC results, review rows, notifications, announcements, and comments.
- Add the per-operation rollout capability manifest.
- Add injected API/storage interfaces and deterministic Phase 1 fixtures usable only in tests and explicit `__DEV__` fixture mode.
- Add a visible development-data notice; fixture actions must never call Supabase.
- Preserve the web baseline at `508aabc` until mobile compatibility is implemented and verified.

Live gate:

- Type generation and read-only deployed inspection may proceed.
- Do not reapply the supplied SQL.
- Enabling a live operation requires its own probe, not closure of every release gate.

Tests:

- Generated types compile unchanged.
- Runtime schemas reject malformed/unknown fields safely.
- Fixture mode is impossible when `__DEV__` is false.
- Capability flags hide actions but do not alter authorization payloads.
- `npm run check`; run `npm run build:verify` if config/dependencies change.

### P1-FI.1 — Complete the read journey and guarded routes

Purpose: finish the user-visible read path shared by every later mutation.

Implementation:

- Add My Subtasks, Work I Am Leading, and Deadlines views using paged virtualized lists.
- Complete task detail: requirements, dependencies, team/reviewer summary, subtasks, readiness, history, submissions, and related-project link.
- Complete subtask detail: prerequisites, progress, immutable attempts, reviewer feedback, and evidence metadata.
- Add signed evidence open actions behind `evidenceSignedRead`; keep URLs in memory for at most the approved lifetime.
- Add review list/detail route adapters with UUID validation and fresh RLS-backed reads.
- Treat forbidden, deleted, and missing records as one unavailable state where distinguishing them would leak existence.
- Preserve current Projects and Inbox routes.

Live gate:

- Existing task/subtask reads continue.
- Enable each new read only after one allowed and denied RLS probe.
- Signed evidence remains disabled until private read and expiry behavior are accepted.

Tests:

- Pagination, deduplication, filter/sort/deadline rules, and scoped query keys.
- Loading, empty, cached-offline, error, unavailable, and refresh states.
- Direct-link access for signed-out, unauthorized, malformed, deleted, and allowed records.
- Accessibility labels and realistic list virtualization.

### P1-FI.2 — Start/resume work and text-only progress

Purpose: deliver the first safe execution mutations before file transfer.

Implementation:

- Add Start/Resume through `transition_task_status`; never update `tasks.status` directly.
- Re-read status after an ambiguous response. If the task is already `in_progress`, show the authoritative state rather than submitting again.
- Build the keyboard-safe progress form for percent `0..99`, blocker category/details, next step, and note.
- Call `save_subtask_progress` with no attachment for the first live slice.
- Check assignment/dependencies/status for UX, then surface the server rejection if state changed.
- Make both mutations online-only with no automatic retry or replay.

Live gate:

- Assigned contributor succeeds.
- Unassigned, inactive, stale-state, completed/locked, dependency-blocked, and malformed calls return safe errors.

Tests:

- RPC payloads and returned-row mapping.
- Success, duplicate press, offline, timeout reconciliation, stale status, unauthorized, and server rejection.
- Exact cache invalidation and disabled/loading accessibility state.

### P1-FI.3 — Evidence rules, native binary transport, cleanup, and signed reads

Purpose: build one reusable private-file boundary for progress and both submission levels.

Implementation:

- Query and cache `get_task_evidence_rules()` per environment/session.
- Normalize picker assets to name, MIME, byte length, URI, source, and stable local selection ID.
- Validate nonempty size, exact server maximum, MIME allowlist, count, duplicates, and sanitized display names.
- Implement documented path builders and random unique prefixes.
- Implement cancellable URI-to-ArrayBuffer conversion and `upsert: false` upload.
- Complete the >6 MiB transport spike before claiming support for the 50 MiB contract.
- Add upload progress where the selected transport exposes trustworthy progress.
- Implement claim-before-remove cleanup sequentially for each path.
- Implement signed read at the approved short lifetime with no persistence.
- Add the image-picker config plugin and permission copy.

Live gate:

- Allowed assignee/Task Lead upload succeeds.
- Unrelated, inactive, anonymous, malformed-path, wrong-task, other-owner, overwrite, update, and premature-delete operations fail.
- Bucket is private with matching size/MIME configuration.
- Claim/delete and finalized-seal behavior pass.

Tests:

- Rules mapping, empty/size/MIME/count/duplicate/name/path boundaries.
- Picker cancellation, denied permission, missing metadata, Android content URI, and iOS file URI.
- Upload cancellation and failure at every file position.
- Claim-before-remove ordering, partial cleanup, deletion retry, finalized denial, and redacted errors.
- Native Android/iOS files at the transport boundaries.
- `npm run check` and `npm run build:verify`.

### P1-FI.4 — Evidence-backed progress and subtask submission

Purpose: complete the employee half of the vertical slice.

Implementation:

- Add optional progress evidence using the shared upload/cleanup service.
- Build the subtask submission screen with nonempty note and one-to-ten evidence files.
- Generate the submission UUID before upload.
- Upload each file to the exact subtask attempt path, then call `submit_subtask_for_review` once.
- Reconcile timeouts by submission UUID before cleanup or retry.
- On confirmed failure, claim and remove only objects from that attempt.
- Refresh subtask, parent task, lists, progress, submissions, history, review inbox, and notifications after success.
- Preserve prior attempts and evidence as immutable.

Live gate:

- Assigned contributor success with real evidence.
- Unassigned, stale, duplicate, bad path, foreign object, wrong owner, unsupported/oversized/eleventh file, and late attachment insertion are rejected atomically.
- Correct effective Task Leader receives the review route/notification.

Tests:

- Submission payload and metadata mapping.
- Success, offline, duplicate press, timeout committed/not committed, server rejection, partial upload, cleanup failure, and retry.
- No false success and no client deletion of finalized evidence.

### P1-FI.5 — Subtask review and changes-requested loop

Purpose: close delegated-work review before parent submission.

Implementation:

- Build a paged pending-subtask review inbox using stored `reviewer_id` and RLS.
- Show contributor, attempt/version, note, progress/blockers, evidence, prior feedback, parent task/project context, and reviewer identity.
- Generate evidence links only when opened.
- Require explicit confirmation for approval and nonempty feedback for changes requested.
- Call `decide_subtask_review` online with no retry.
- Re-read affected records after ambiguous responses.
- Preserve earlier attempts/evidence and return the current subtask to the server-defined rework state.

Live gate:

- Correct reviewer can act.
- Submitter, unrelated user, wrong reviewer, stale recommended lead, self-review collision, already-decided attempt, and inactive actor cannot act.

Tests:

- Approve, request changes, resubmit, and approve again.
- Empty feedback, self-review, wrong reviewer, stale/duplicate decision, offline, timeout, and server error.
- Immutable history and exact invalidation.

### P1-FI.6 — Parent task submission and primary/backup review

Purpose: complete the parent workflow.

Implementation:

- Present readiness from live child status; `100%` or `for_review` is not completion.
- Recheck readiness and reviewer immediately before uploading.
- Build optional parent evidence and required-note behavior exactly as returned by the deployed contract.
- Generate a task submission UUID, upload to the task path, and call `submit_task_for_review` once.
- Apply the same timeout reconciliation and cleanup rules as subtask submission.
- Build task review inbox/detail and call `decide_task_review` with no retry.
- Display primary/backup routing without implying both can always act.
- Refresh task, subtasks, lists, reviews, submissions, history, deadlines, notifications, and project rollup.

Live gate:

- Effective Task Lead can submit only when every subtask is approved.
- Correct primary/backup reviewer can act according to the stored route.
- Submitter/self-review, unfinished child, wrong reviewer, dependency block, stale status, duplicate submission, and duplicate decision fail.

Tests:

- Full readiness matrix.
- Optional/no evidence and evidence upload paths.
- Primary/backup routing, self-review, changes requested, resubmission, approval, timeout reconciliation, and immutable versions.

### P1-FI.7 — Notifications, announcements, comments, and foreground Realtime

Purpose: make the live workflow discoverable without Phase 3 push/chat scope.

Implementation:

- Extend the existing notification feature with unread count, mark-one, and mark-all using recipient-owned writes.
- Preserve the existing safe handling of unknown/finance notification types.
- Add Phase 1 task/subtask/review destinations with UUID validation and fresh authorization reads.
- Add published announcement list/detail, expiry/audience handling, and recipient read state.
- Add text-only task comments only if participant read/insert RLS is confirmed; derive sender from `auth.uid()`.
- Refactor the Realtime helper to support scoped feature channels without replacing the existing profile/permission subscriptions.
- Subscribe only to confirmed publication tables; validate IDs, deduplicate, and invalidate scoped queries.
- Refresh once on reconnect and remove channels on unmount, sign-out, account change, and permission revocation.

Live gate:

- Notification read/write is recipient-only.
- Announcement visibility/read state matches audience and expiry.
- Comment read/send is participant-only.
- Unrelated accounts receive neither protected rows nor Realtime events.

Tests:

- Notification unread/dedupe/read-one/read-all and safe destinations.
- Announcement audience/expiry/read/search/empty/error states.
- Comment length, sender spoofing, unauthorized task, duplicate send, offline, and pagination.
- Realtime event mapping, duplicate events, reconnect, invalidation, and cleanup.

### P1-FI.8 — Authentication, account, and lifecycle hardening

Purpose: close Phase 0 dependencies used by the completed Phase 1 flow.

Implementation:

- Verify active employee, Task Lead, primary reviewer, and backup reviewer sign-in/session restore/token refresh/sign-out.
- Confirm inactive, missing, malformed, and unsupported profiles fail closed.
- Add minimal account/profile/organization/permission display.
- Add notification preferences only after an own-profile write contract is confirmed.
- Clear all protected caches, mutation state, evidence selections, signed URLs, Realtime channels, and pending navigation on sign-out/account switch.
- Reauthorize every protected deep link after cold start.

Tests:

- Session restoration, refresh, stale/expired session, sign-out, and user switching.
- Unauthorized cached screen/deep-link denial.
- Own-profile preference success and another-user denial if enabled.

### P1-FI.9 — Non-production, device, and release acceptance

Purpose: prove Phase 1 as one real workflow.

Implementation:

- Add an explicitly invoked non-production integration harness separate from Jest unit tests.
- Require environment variables for project ref, test identities, and fixture record IDs; abort unless the configured project is the approved non-production ref.
- Never print passwords, tokens, private paths, signed URLs, notes, or personnel data.
- Run the complete employee -> subtask review -> rework/approval -> parent review -> final status journey.
- Run allowed/denied Storage/RPC/RLS and two-client Realtime probes.
- Test airplane mode, reconnect, background/foreground, process restart, token refresh, account switch, stale links, interrupted upload, and cleanup recovery.
- Test realistic lists, keyboard, safe areas, touch targets, screen readers, enlarged text, contrast, and picker/file behavior on Android and iOS.
- Scan source, bundles/source maps, logs, screenshots, and fixtures for secrets and protected data.
- Update the roadmap, contract notes, parity matrix, baseline record, and blocker report with verified results.

Required commands:

- Targeted test files during every package.
- `npm run check` after every executable package.
- `npm run build:verify` after routes, app config, dependencies, native picker/upload behavior, or build scripts change.
- Final clean-install `npm run check` and `npm run build:verify`.

## Exact live-blocker reporting

When an integration fails, do not mark the whole phase blocked. Record:

```text
Package/blocker:
Operation: exact table/Storage/RPC operation
Project ref:
Actor: role plus assignment/reviewer/organization relationship
Record state:
Expected result:
Actual status/code and redacted message:
Reproduction test:
Minimum backend change:
Mobile work continuing in parallel:
```

## Test matrix

| Area | Automated evidence | Deployed/device evidence |
| --- | --- | --- |
| Contracts | Generated types, runtime schemas, malformed rows | Deployed signatures/grants match source |
| Tasks/subtasks | Mapping, filters, readiness, pagination, errors | Assigned/leading/unrelated RLS |
| Start/progress | Payload, offline, stale, timeout, invalidation | Allowed contributor and denied actors |
| Evidence | Rules, path, size/MIME/count, transport, cleanup, signed URL | Android/iOS upload/open and Storage denial matrix |
| Subtask submit/review | Payload, reconciliation, immutable versions, decisions | Contributor/reviewer/self-review/unrelated |
| Parent submit/review | Readiness, cleanup, primary/backup, duplicates | Full completion and changes-requested loop |
| Notifications | Mapping, unread, dedupe, safe navigation | Recipient-only read/write and live workflow notice |
| Announcements/comments | Audience, expiry, validation, participant scope | Web/mobile cross-client behavior |
| Realtime | Mapping, duplicate, reconnect, cleanup | Authorized two-client event and unrelated denial |
| Auth/lifecycle | Restore, refresh, sign-out, user switch, stale link | Android/iOS cold/background/reconnect |
| Accessibility/privacy | Labels, disabled/error state, redaction | Screen reader, enlarged text, bundle/log scan |

## Manual Android and iOS checklist

- [ ] Active employee and reviewer sign-in, cold restore, refresh, sign-out, and account switch.
- [ ] My Tasks, My Subtasks, Leading Work, and Deadlines with empty and realistic data.
- [ ] Allowed and denied direct links to task, subtask, review, announcement, and project routes.
- [ ] Document/image cancellation, permission denial/retry, MIME/size/count boundaries, and local URI handling.
- [ ] Standard/resumable upload boundary selected by the transport spike.
- [ ] Upload cancellation, partial failure, RPC timeout reconciliation, cleanup claim, deletion retry, and orphan-worker fallback.
- [ ] Progress and evidence-backed subtask submission.
- [ ] Subtask request-changes, resubmit, approve, and immutable history.
- [ ] Parent submission remains blocked until all children are approved.
- [ ] Primary/backup task review and self-review denial.
- [ ] Notification read state, announcement audience/expiry, and safe navigation.
- [ ] Text comment synchronization if enabled.
- [ ] Web-to-mobile and mobile-to-web foreground Realtime plus cleanup.
- [ ] Airplane mode does not queue or replay mutations.
- [ ] Keyboard, safe areas, light/dark appearance, enlarged text, screen reader, contrast, and touch targets.

## Phase 1 completion checklist

- [ ] Roadmap and contract record reflect commit `042e1a5b` and the evidence migration.
- [ ] Generated types include `get_task_evidence_rules` and `claim_task_evidence_cleanup`.
- [ ] Per-operation live capabilities have recorded allowed/denied evidence.
- [ ] Employee can browse assigned tasks/subtasks, leading work, dependencies, deadlines, history, feedback, and related project context.
- [ ] Employee can start eligible work and save progress.
- [ ] Native evidence validates, uploads privately, cleans up safely, and opens through short-lived authorized access.
- [ ] Employee can submit, receive requested changes, resubmit, and reach subtask approval.
- [ ] Effective Task Lead can submit a parent only after every subtask is approved.
- [ ] Correct primary/backup reviewer can request changes or approve; self-review and unrelated actors are denied.
- [ ] Submission versions and finalized evidence remain immutable.
- [ ] Notifications and announcements have server-backed read state and safe navigation.
- [ ] Text-only comments are participant-authorized, or their exact missing live contract remains the only open communication item.
- [ ] Foreground Realtime updates invalidate the correct queries and every subscription cleans up.
- [ ] Sensitive mutations are online-only, not retried or replayed automatically.
- [ ] `npm run check` and `npm run build:verify` pass after final changes.
- [ ] Android and iOS manual acceptance is recorded.
- [ ] No unresolved high-severity authorization, self-review, cleanup, immutable-history, session-leak, or secret-leak issue remains.

## Recommended implementation order

1. P1-FI.0 contract/type adoption and development fixtures.
2. P1-FI.1 complete read journey and guarded review routes.
3. P1-FI.2 start/resume and text-only progress.
4. P1-FI.3 evidence transport, cleanup, and signed reads.
5. P1-FI.4 subtask submission.
6. P1-FI.5 subtask review and rework loop.
7. P1-FI.6 parent submission/review.
8. P1-FI.7 communications and Realtime.
9. P1-FI.8 auth/account lifecycle hardening.
10. P1-FI.9 integrated non-production and Android/iOS sign-off.

Each package ends with truthful status: implemented with fakes, live-integrated, or release-verified. No package is described as complete merely because its screen renders.

## Implementation update — August 31, 2026

- **Implemented, live-gated:** regenerated database types; capability/fixture controls; online-only workflow adapters; task start/resume; subtask progress; evidence-rule parsing, immutable paths, upload, signed-read and claim-before-remove helpers; subtask/task submit/review screens; reviewer inbox; recipient notification writes; announcement and comment screens; scoped foreground Realtime invalidation; and associated unit/component tests. Native tab navigation is limited to five items, with Reviews, Notices, and Settings available through More stack routes.
- **Not live-verified:** every capability remains disabled unless the matching allowed/denied backend probe is recorded. No migration was rerun and no authorization/security bypass was introduced.
- **Validation:** `npm run check` passed with 52 suites / 161 tests. `npm run build:verify` is blocked by a Windows Hermes `spawn UNKNOWN` failure; Android and iOS no-bytecode exports succeeded with one worker. Real Android/iOS picker/upload/notification/Realtime acceptance still remains required.
