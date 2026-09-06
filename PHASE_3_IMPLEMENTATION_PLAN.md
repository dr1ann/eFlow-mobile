# Phase 3 Full Integration Implementation Plan — Notifications, Chat, Briefs, and Proposal Import

## 1. Status and implementation baseline

- Plan revised: September 3, 2026.
- Status: P3-FI-0 foundations, P3-FI-1 Inbox behavior, and development-only P3-FI-3/P3-FI-5 foundations are implemented locally; individual live integrations and release acceptance remain subject to the gates below.
- This replaces the August 30 partial Phase 3 plan. It does not mark Phase 3 fully integrated or complete.
- Mobile commit inspected: `3921e63e23b6b417099cf2da0636f7dd1a8e53c5` — guarded Phase 2 project lifecycle integration.
- Phase 1 workflow commit: `b135a77e59f590b381ada919cb3a81067441acd9`.
- Mobile working tree was clean before this documentation change.
- Stack: Expo `~57.0.18`, React Native `0.86.3`, TypeScript, Expo Router, Supabase, and TanStack Query.
- Recorded web compatibility baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`.
- Remote web `main` checked September 3: `042e1a5b240cf667eb3dfa69d263897686de2a04`.
- The web source was read from that Git commit, not the older local checkout or its unrelated working changes.
- The newer web SHA is an inspection reference. Do not replace the adopted baseline until compatibility is implemented and verified.

References: [repository instructions](AGENTS.md), [roadmap](MOBILE_IMPLEMENTATION_PHASES.md), [Phase 3 contract ledger](docs/PHASE_3_CONTRACTS.md), [Phase 2 plan](PHASE_2_IMPLEMENTATION_PLAN.md), and [development/integration/release report](PHASE_1_TO_3_BACKEND_BLOCKER_REPORT.md).

Phase 1 is accepted as the foundation for continuing development. The user has reported successful task and subtask approvals on mobile; those observations do not substitute for the remaining role-denial and Android/iOS acceptance matrix. Phase 2 has project reads, creation, readiness, completion, and archive adapters; reports and reusable queued AI jobs are still absent. Only the Phase 3 features that consume those absent contracts depend on them.

This task produces planning documents only. Future mobile implementation must not apply or rerun teammate-owned migrations, modify the shared backend, provision push infrastructure, or send test pushes without the relevant implementation authority and environment configuration.

## 2. Intended outcomes and scope

The full-integration target covers the four main Phase 3 journeys already described in the roadmap:

| Journey | Final user outcome |
| --- | --- |
| Notifications and push | Receive an eligible business alert, open it after session restoration, reach an authorized record, and keep inbox/unread state consistent. |
| Standing organization/task chat | Read paged history, send text, mark history read, edit own messages, react, and share private attachments within authorized channels. |
| AI management briefs | Request a brief for an authorized report, leave or restart the app, and return to a structured advisory result with source/freshness information. |
| Proposal PDF import | Upload a private PDF, resume server extraction/decomposition, edit a saved draft, follow its actual approval route, and explicitly commit an eligible revision through an atomic, in-scope server operation. |

A text-only chat milestone or proposal draft-only milestone is useful progress, but it does not satisfy the full corresponding journey.

Budget, funding decisions, petty cash, receipts, liquidation, and financial mutations remain **Phase 4 or later**. Proposal import cannot silently reintroduce them. Audio/video calls, direct messaging, broad contact discovery, advanced moderation, desktop governance authoring, and full manual work-plan creation are outside this plan. Work templates, productivity/performance views, and native report export remain separately approved candidates; this plan does not automatically select them.

Ordinary tasks, projects, and reviews must remain usable when push delivery or AI is unavailable.

## 3. Current mobile inventory

| Existing code | Reuse and remaining work |
| --- | --- |
| `src/features/notifications/api/notifications-api.ts` | Recipient-scoped 25-row reads and canonical-row lookup exist. Mark-one and mark-all adapters also exist; mark-all UI and bounded result semantics remain to implement. |
| `src/features/notifications/screens/notification-list-screen.tsx` | Paged Inbox, mark-one UI, and recipient-filtered Realtime invalidation exist behind Phase 1 flags. Its unconditional read-only banner is stale when those flags are enabled; mutation errors are not surfaced by the screen. |
| Notification mapping/navigation/query tests | Preserve task/project UUID validation and unknown-type redaction; extend for canonical re-fetch on every open, response recovery, filters, unread totals, and new proven destinations. |
| `src/lib/phase-1/capabilities.ts` | `notificationWrites` and `phase1Realtime` already own the shared notification behaviors. Do not introduce a second contradictory gate for them. |
| `src/lib/gateway/client.ts` | Bearer auth, typed responses, timeouts, cancellation, and safe endpoint refresh exist. There is no feature-level resumable job manager or brief/import API. |
| Query/auth/Realtime helpers | Reuse AppState/NetInfo integration, protected cache cleanup, scoped subscriptions, and narrow invalidation. |
| Phase 1 file picker and evidence modules | Reuse native availability checks, metadata normalization, file validation patterns, and tests. Evidence path/cleanup RPCs are task-specific and must not be applied to chat or proposal files. |
| Protected navigation | Five bottom tabs already exist. Add advanced entry points under More and existing contextual screens, not additional native tabs. |
| Native configuration | Document/image pickers, SecureStore, and `expo-constants` exist. `expo-notifications`, an EAS project ID, and an iOS bundle identifier are not declared in the inspected package/app configuration. |

No push or live standing-chat, management-brief, or proposal-import integration exists. P3-FI-3 now has an explicitly selected, development-only synthetic chat preview under More; it neither reads nor writes eFlow chat data. P3-FI-5 now has shared typed job-state/backoff and secure identifier persistence used by no live endpoint yet. The supplied test task SQL and manually exercised records are testing data, not Phase 3 source changes or authorization evidence.

## 4. Upstream comparison and actual integration gaps

The `508aabc..042e1a5` comparison adds the task evidence, cash-release override, and project-completion migrations. None adds device push registration, a push sender, typed brief jobs, or server PDF extraction. Proposal/collaboration presentation changes are present. Existing behavior and its limits must still be audited at the inspected commit.

| Source evidence at `042e1a5` | Consequence for this plan |
| --- | --- |
| `supabase/fresh_schema.sql` defines base chat tables and policies. | Correct the old “no base chat DDL” blanket claim: source exists, but deployed policy convergence and safety are unverified. |
| That file grants authenticated users broad channel/member writes (`cc_write`, `ccm_write`). Message insert checks sender ID and membership, but names/read timestamps are supplied by the client. | Verify/remove permissive policy paths and enforce authoritative membership/actor/read-cursor rules before live chat enablement. A new restrictive policy alone does not neutralize an existing permissive policy. |
| Notification source policies scope reads/updates to `user_id`, while insert permits any authenticated caller; the email route accepts client-selected recipient/content. | Verify actual grants, active-profile denial, read-column restrictions, and trusted event creation. Do not reuse the email route as a push sender or assume type allowlisting alone proves content privacy. |
| `server/routers/ai.py` exposes generic POST jobs/chat and GET job status under `/controlpanelEflow/api/ai`. Clients supply model/messages. | Existing transport can be reused, but typed brief/import contracts are still needed. No cancel business endpoint is evidenced here. |
| `managementBriefService.ts` builds a prompt from report rows in the browser. | Use a server report reference/filter contract and server-owned context; do not port the prompt builder. |
| `pdfTextExtractor.ts` uses browser `File` and `pdfjs-dist`. | Server extraction/OCR and a typed decomposition job are separate integration requirements. |
| Collaboration migrations define private `proposal-drafts` Storage, draft/revision/review operations, and `commit_collaboration_draft(p_draft_id, p_revision_id)`. | Build around these real contracts after checking source association, cleanup, revision conflicts, permissions, and final side effects. |
| `publish_department_proposal(p_draft_id)` finalizes the latest working snapshot for owner-only department plans. External collaboration has separate review requirements. | Do not invent a mandatory external approval for department-only drafts or let this one-argument API publish an unseen concurrently changed snapshot. |
| The latest source `commit_single_department_proposal_budget` in `20260824000007_task_budget_daily_petty_cash_workflow.sql` requires a funding schedule and locked owner budget, then writes commitments and potentially allocations/ledger rows. Even no-cost choices still pass through the commitment path. | Full mobile proposal commit has a concrete conflict with the Phase 4 finance deferral. It stays gated until the backend supplies a supported non-financial commit path with verified side effects, or the product scope is explicitly revised. Do not fabricate no-cost values. |
| Revision save/autosave signatures do not expose an expected revision/version argument in the inspected source. | Detecting changes with a client re-fetch is useful UX but not atomic conflict protection. Require a compare-and-save contract or verified equivalent before claiming concurrent draft editing is safe. |
| Legacy `commitProposalDrafts.ts` loops over project/task creations. | Do not use it for mobile import; partial hierarchy creation is not an atomic commit. |

These are source findings, not claims about observed live HTTP/SQL errors. No backend mutation, migration, identity probe, or push delivery was executed while writing this plan.

## 5. Development, integration, and release gates

Track every operation independently in the contract ledger:

1. **Mobile development:** build screens, validators, deterministic fake adapters, lifecycle recovery, and tests now. Development fixtures must be explicitly selected, visibly labeled, use synthetic data, and make no live writes. Production builds must reject fixture mode.
2. **Live integration:** connect only an existing, documented contract with the required per-operation authorization and data-shape checks. Missing contracts stop that adapter, not unrelated features.
3. **Release verification:** record positive/negative identity probes, device acceptance, outages, restart/revocation handling, and native builds before marking the workflow complete.

There must be no automatic fallback from a failing live request to mock success. Development completion, live enablement, and release acceptance are separate fields. An unfinished push sender does not block chat UI; absent reports block live briefs only; the proposal funding conflict blocks proposal commit only.

### Capability ownership

Add `src/lib/phase-3/capabilities.ts` and tests during implementation. Use an explicit `EXPO_PUBLIC_PHASE_3_LIVE_CAPABILITIES` allowlist with unknown values ignored and empty/default configuration disabled.

Planned capability families, to be finalized with the ledger:

- Notification summary/count reads; existing mark-read and foreground notification subscriptions retain their Phase 1 owners.
- Push device registration/preferences; the trusted sender is controlled by the backend, never by a client flag.
- Chat reads, send, read state, edits, reactions, and attachments.
- Brief job create/status/cancel, enabled only for supported server operations.
- Proposal drafts, source upload/read, extraction/decomposition jobs, review, and final commit.

Flags control presentation and requests, not security. Every route and action also needs the exact effective permission and fresh server record scope. Production cannot enable a feature merely because its mock tests passed.

## 6. Roles and authorization

| Actor | Intended access | Required denial |
| --- | --- | --- |
| Active notification recipient | Own Inbox, read state, own installation preferences | Another recipient's row, token, or response target |
| Current organization/task channel participant | Only channel actions granted by its verified contract | Joining arbitrary channels, spoofing sender, reading after removal |
| Assigned employee / effective Task Leader | Existing work permissions and channel participation from persisted relationships | Leadership title alone granting department reports or proposal commit |
| Authorized Head / Assistant Head | Report/brief and draft actions within the actual organization/project contract | Out-of-scope reads and operations not explicitly granted |
| Assigned proposal reviewer | Decide only the relevant revision when the backend routes review to that actor | Forged approvals, stale revisions, unauthorized own-review shortcuts |
| Ordinary project member | Project and chat reads only where independently authorized | Membership alone granting draft/report/management authority |
| Super Admin | Verified operational oversight reads | Blanket operational mutation access based on the role shortcut |
| Inactive, missing, unrelated, or unsupported profile | No protected access | Cached-content leaks, guessed IDs, or stale-session success |

Resolve Assistant Head and Super Admin behavior per operation; do not freeze all Phase 3 work while one role/action remains undefined. Tests must use actual relationship fixtures, not just role labels. Keep review rules specific: task self-review rules from Phase 1 must not be indiscriminately applied to a distinct, verified department proposal publication contract.

## 7. Work packages

### P3-FI-0 — Refresh contracts, fixtures, and access boundaries

**Implementation record — September 3, 2026**

- Added the fail-closed Phase 3 capability allow-list and production-rejected fixture mode with tests.
- Added the shared job contract and SecureStore persistence for opaque job/reference IDs only. Prompts, results, report content, PDF bytes, signed URLs, and tokens are not persisted.

**Work**

- Record current mobile/upstream/deployed versions and actual operations in `docs/PHASE_3_CONTRACTS.md`; retain inspection vs adoption distinction.
- Audit deployed grants/policies/RPCs read-only when access is available. Do not equate missing CLI migration history with a missing schema or rerun migrations.
- Define typed feature adapters and explicit synthetic fixture scenarios for permitted, forbidden, empty, offline, conflict, and server-error states.
- Add only the contracts and shared helpers the next workflow uses; extend shared jobs when brief and import both need them.
- Track missing operation, expected actor/relationship, actual observed response or “not probed,” minimum backend change, and mobile work continuing.
- Regenerate database types after a confirmed schema change with `npm run supabase:types`; inspect the result before adoption.

**Acceptance/tests**

- Capability/fixture tests cover production rejection, unknown flags, exact permission, and user/environment separation.
- No new contract name or endpoint is represented as deployed without source/deployment evidence.
- Existing Phase 1/2 behavior remains intact.

### P3-FI-1 — Finish the canonical notification workflow

This is the first complete mobile increment and has no AI dependency.

**Implementation record — September 3, 2026**

- Added All/Unread filters, recipient-scoped server unread count support behind `notificationSummary`, visible mutation feedback, a mark-all action that does not download changed IDs, and cache invalidation for all feed filters/counts.
- Opening a notification now first reads its canonical recipient-scoped row before navigating; the destination performs its own protected read.
- The mark-all endpoint has no verified cutoff/count RPC, so the UI deliberately avoids a fabricated affected-row count and warns that concurrently arriving events can remain unread.
- These are local/mobile changes only. The existing Phase 1 live write and Realtime flags retain ownership, and recipient-policy probes remain required before release enablement.

**Work**

- Reuse the existing feed and mutation functions. Add All/Unread filters, server-scoped unread totals, mark-all UI, pending/error feedback, and retry.
- Replace the unconditional read-only banner with accurate capability-dependent states.
- Resolve every open through `getNotificationForRecipient`, then validate the destination and let its screen re-fetch under RLS. Cached list content never authorizes navigation.
- Preserve supported task/project destinations first. Add subtask/review/chat/draft destinations only when a canonical server reference and corresponding screen exist; never infer a subtask UUID from task title/text.
- Use a stable pagination tuple and deduplicate new events. Unread totals must not be calculated from just the currently loaded page.
- Bound mark-all processing. Prefer a server count/high-watermark operation; do not download every notification ID merely to report a count. Notifications arriving after the captured boundary remain unread.
- Keep notification and unread keys in sync after marks, events, reconnect, and returning from a destination.
- Require safe event categories/projection for finance or unknown content, including types reused across business domains. Do not select financial detail solely to decide how to hide it.
- Prove that recipients can change only their own allowed read fields; identity, source content, and recipient ownership remain server-controlled.

**Tests/acceptance**

- Extend existing API, query, navigation, mapper, and screen tests for errors, filters, counts beyond 25 rows, boundary duplicates, mark-all races, stale targets, and permission removal.
- Verify allowed/denied reads and read updates, inactive users, publication delivery, reconnect, and sign-out cleanup.
- Outcome: an authorized user can receive, open, and mark a canonical notification with truthful state and failure feedback.

### P3-FI-2 — Push registration, delivery, and response recovery

**Backend/infrastructure contract**

- Team-owned Expo Push Service is the planning default from the roadmap; confirm the existing project/credential owner before provisioning or deployment.
- Authenticated registration/upsert/revoke for a user and app installation, with server-derived user, environment/app identity, token uniqueness/rotation, last-seen, preference categories, and expiry/revocation.
- Token enumeration and send authority restricted to trusted infrastructure.
- Canonical notification event -> delivery outbox -> preference/eligibility check -> sender -> ticket/receipt processing -> retry or invalid-token disablement.
- Deduplicate by canonical event, device, and environment; retry transient failures with bounds. Delivery receipts are delivery evidence, not proof the user read the event.
- Define offline sign-out behavior explicitly. Local sign-out must complete even if revoke fails; use generic payloads and a server registration/session lease or equivalent to limit stale delivery until cleanup. Never promise instant server revocation without connectivity.

**Mobile work**

- Add SDK-compatible `expo-notifications` using `npx expo install expo-notifications` when implementing this package. Add other native packages only if the selected implementation needs them.
- Configure the plugin, team-owned EAS project ID, Android channels, and approved iOS application identity/entitlements. Rebuild and reinstall the development client before device testing.
- Isolate native loading/availability so an older client or unavailable module produces a scoped useful state rather than a launch crash.
- Offer opt-in under Settings or a relevant Inbox explanation; allow “not now,” denied/system settings, and per-category preferences.
- Read/acquire/rotate the token without rendering or logging it; register only after an active authorized session.
- Implement one response coordinator for initial responses and live listeners. Wait for auth, profile, permissions, navigation readiness, and canonical recipient lookup; deduplicate repeated response delivery and clear consumed native response state.
- Proposed payload v1: `{ version: 1, notificationId: UUID }`. This is a proposed backend agreement, not an existing deployed shape. Do not accept arbitrary URL navigation or private content from the payload.
- On account switch, discard pending response state and re-resolve for the new recipient. Never open the old user's cached destination.
- Update canonical counts after foreground receipt without inserting a second synthetic Inbox row.

**Tests/acceptance**

- Permission states, missing native module/project ID, offline acquisition/revocation, duplicate/rotated tokens, account switch, forged payload, deleted record, and listener disposal.
- Sender tests: event allowlist, preferences, retry/receipts, invalid tokens, wrong environment, and client inability to select recipients/content.
- Android/iOS foreground, background, and terminated-launch acceptance, with app restart and permission changes. Use development builds; Expo Go is not the acceptance target.
- Push setup follows the [SDK 57 notification reference](https://docs.expo.dev/versions/v57.0.0/sdk/notifications/) and [Expo push setup](https://docs.expo.dev/push-notifications/push-notifications-setup/). Export success alone does not verify installed native modules or push credentials.

### P3-FI-3 — Standing chat history, text send, and read state

**Implementation record — September 3, 2026**

- Added a synthetic, opt-in development preview under More with channel/message list, compose validation, deterministic message reconciliation, and accessible native controls.
- It is hidden unless `EXPO_PUBLIC_PHASE_3_USE_FIXTURES=true` in a non-production build and labels every surface as local-only. It does not prove membership, send/read state, Realtime, edits, reactions, attachments, or any live chat authorization.

**Contract work**

- Reconcile `fresh_schema.sql`, membership-sync migrations, actual grants, and deployed policies; test self-enrollment and membership enumeration explicitly.
- Use server-maintained task/organization membership and define history access after removal, empty teams, deleted/archived tasks, and re-joining.
- Freeze narrow channel summaries and cursor-paged messages; default presentation page sizes may be 25 channels / 50 messages, bounded by the backend.
- Require server-derived sender identity/name and timestamp, message-length validation, idempotent client message key, and a read cursor bounded by messages actually displayed.
- A send RPC must not leave a direct insecure insert path available. Prefer server timestamps/cursors over trusting the phone clock.

**Mobile work**

- Add channel list and message screen under More, plus a contextual task-chat entry when authorized.
- Keep Phase 1 task comments separate from standing chat; do not merge their tables or claim one replaces the other.
- Maintain scroll position while loading earlier pages; deduplicate/reconcile response and Realtime events by stable ID/client key.
- Keep draft text in memory initially. Show a failed send and explicit retry; do not automatically replay after reconnect.
- Advance read state only for the visible, focused channel/messages. Refresh channel unread summaries on resume.
- On membership denial/revocation, close the protected conversation and remove its cached data/subscription.

**Tests/acceptance**

- Paged/empty history, ties/out-of-order messages, duplicate sends, ambiguous timeout reconciliation, read-cursor races, spoofed actor, removed member, and cross-organization access.
- Keyboard, long text, screen reader labels, older-page scroll anchoring, and large histories on both platforms.
- Text chat may ship as an independently verified increment; P3-FI-4 still remains for the full chat scope.

### P3-FI-4 — Chat edits, reactions, and private attachments

**Work**

- Add author-limited message edits with a server-defined edit window/version conflict rule and visible edited state.
- Add first-class reaction rows/operations with actor uniqueness and idempotent toggles; do not mutate reaction JSON inside message text.
- For legacy encoded messages, define a tested compatibility decoder or server projection; never expose raw embedded metadata as conversation text.
- Add authorized private attachment upload, finalized message metadata, signed reads, and failure/expiry cleanup with a server-owned association contract.
- Revalidate type/size, sanitize filenames, reject unsupported media, and preserve progress/cancel/retry states. Server limits and policy paths remain authoritative.
- Do not copy task evidence cleanup claims into the chat bucket. Handle ambiguous message creation by reconciling association before cleanup.
- Replies, mentions, deletion/moderation, and attachment preview variants can be added only if separately selected and supported; edits/reactions/attachments above remain part of the main roadmap target.

**Tests/acceptance**

- Author/non-author edits, stale edit, reaction duplication/removal, missing/deleted message, legacy decode, and concurrent Realtime events.
- Allowed/denied private file paths/metadata, invalid MIME/size, upload failure, commit ambiguity, expired signed access, membership removal, and native URI handling.

### P3-FI-5 — Resumable job support and typed management briefs

**Implementation record — September 3, 2026**

- Added accepted job states, bounded foreground polling/backoff helpers, terminal-state handling, and compact account/environment-scoped persistence with corruption and expiry cleanup.
- No live brief/import route is wired because a typed, scoped backend contract and report DTO are still absent.

**Dependency:** live briefs need the Phase 2 report contract and a typed gateway operation. Build the UI/job state machine against synthetic reports/jobs while those are unavailable.

**Required contract**

- Create/status/cancel operations with documented request/response versions, limits, rate/concurrency control, expiry, owner scope, and idempotent creation or request-key reconciliation.
- Request body contains an authorized report identifier/definition plus allowed filters. The server re-authorizes and loads the permitted context; client prompt/model/private notes are not inputs.
- Job IDs are opaque validated server identifiers unless the contract explicitly declares UUIDs.
- Structured result: report version, cutoff/generation time, safe scope label, source-linked observations, and separately labeled advisory recommendations.
- “Verified observations” must come from validated source data/calculation. Unsupported AI claims remain interpretations and cannot acquire verified status from a heading.

**Mobile work**

- Extend the existing gateway client and add shared job state/persistence/hooks only where needed by briefs and proposal import.
- Map queued, running, succeeded, failed, expired, and cancelled server states; “unavailable” is a transport/availability state, not fabricated job success.
- Persist a small versioned record: user/environment, operation, job/request ID, draft/report reference, timestamps and expiry. Keep raw content/results on the server and re-fetch after restart.
- Proposed polling policy: foreground exponential backoff from 2 seconds to a 30-second cap with jitter, at most 5 minutes per active observation session; then require explicit refresh. Respect server Retry-After. Pause offline/background and perform one status refresh on resume.
- Cancel polling on unmount without claiming the server job was cancelled. A cancel action waits for server confirmation and handles a simultaneous successful result.
- Never repeat unsafe creation on endpoint rotation/timeout without the documented idempotency contract.
- Render a brief from an authorized report entry; add a standalone saved-job entry under More only if it rechecks the report scope.

**Tests/acceptance**

- Existing gateway auth/URL/error tests plus job backoff caps, Retry-After, cancellation races, timeout recovery, corrupt/oversized/expired records, restart, and user/environment mismatch.
- Another user's job and revoked report access denied; no prompt/model/private-note payload or automatic assignment/approval.
- AI outage leaves the report and non-AI work available. Brief completion remains gated until a real scoped report is integrated.

### P3-FI-6 — Private proposal source and server extraction/decomposition

**Required contract**

- Define draft creation -> authorized object path -> source association -> processing order. Existing create-draft accepts file metadata while the Storage policy requires an existing manageable draft; establish a safe draft-first source-finalization operation instead of guessing paths or doing broad table updates.
- Validate PDF extension/MIME/signature, server byte/page limits, ownership, checksum, malformed/encrypted/image-only handling, retention, and approved OCR behavior. The phone can precheck bytes/type; it cannot reliably enforce page count without server extraction.
- Existing `proposal-drafts` policy is a source reference. Verify immutable attempt paths, signed reads, final association, cancellation, and authorized orphan cleanup; a private bucket alone is insufficient.
- Typed extraction/decomposition jobs take authorized source/draft references and return bounded structured drafts. Personnel context/model policy remain server-owned.

**Mobile work**

- Select one PDF with the existing native picker, show name/size and upload state, and retain only safe local metadata needed for the active selection.
- Run through shared resumable jobs; after restart re-fetch a saved server draft, or ask for reselection if an unfinished local URI is no longer valid.
- Treat PDF text and AI output as untrusted content; neither can choose actions, permissions, recipients, model, or automatic commit.
- Show extraction failure, OCR unsupported, cancellation, timeout, malformed result, and retry with safe reconciliation.
- Do not persist PDF bytes, extracted text, signed URLs, or raw prompts in generic local storage.

**Tests/acceptance**

- Native picker unavailable/cancel, malformed PDF/MIME mismatch/limits, interrupted upload, private access denial, checksum mismatch, extraction/OCR failures, and source-finalization cleanup.
- Job timeout/restart, malformed/oversized hierarchy, invalid relationships/dates, unexpected finance content, and no raw-content logging.

### P3-FI-7 — Editable saved drafts and actual review routing

**Work**

- Build a bounded editable hierarchy with focused native forms for projects, activities, tasks, schedules, organizations, staffing, and reviewer choices supported by the frozen snapshot schema.
- Validate stable keys, parent references, depth/count limits, active eligible members, leader/team relationship, dependencies/cycles where supported, required titles, and parent/child dates.
- Do not promise imported subtasks unless the final atomic commit contract actually creates them. The inspected commit establishes projects, milestones, and tasks; test returned hierarchy coverage explicitly.
- Separate mutable server autosave from immutable review revisions. Display saving/unsaved/error states; backgrounding flushes only a safe supported save or leaves a clear unsaved warning.
- Require atomic expected-version protection for autosave/revision writes; handle conflicts by refreshing and presenting the changed revision while preserving local edits.
- Render only permitted snapshot fields. A non-financial editor must not overwrite financial fields owned by the web; use a scoped patch/projection contract or keep editing that draft unavailable.
- For external collaborations, follow server readiness, required participant approvals, requested changes, and revision invalidation. For owner-only plans, use the verified department publication route without adding an invented external reviewer.
- Keep final commit separate from saving and requesting review.

**Tests/acceptance**

- Validation boundaries, draft save/reload/restart, stale autosave/revision, removed participant, changed organization/staffing scope, approval binding, and current-version readiness.
- No client-supplied actor/approval claim, self-authorization, financial modification, or broad snapshot leak.

### P3-FI-8 — Explicit atomic proposal commit

This package has the specific finance/scope gate documented in section 4. Continue the preceding draft packages while it is unresolved.

**Contract work and implementation**

- Backend owner must provide or verify a supported operational-only commit that preserves required approvals and creates no financial records. This is a backend/product contract decision, not a mobile flag or a disabled trigger.
- Otherwise keep commit unavailable on mobile and hand off the saved draft to the web. That is partial proposal integration; do not call the full import journey complete.
- Bind confirmation to the exact displayed revision and include a server-enforced expected version or immutable revision ID.
- Preserve the different owner-only vs collaboration publication paths. The current one-argument department publish function can use a newer working snapshot; a client precheck alone does not resolve that race.
- Re-fetch readiness, show the affected project/task counts and review state, then require a separate confirmation.
- Commit through one server transaction with duplicate-safe reconciliation and stable created IDs. The current duplicate rejection must lead to status/result lookup, not a second blind attempt.
- Validate server side effects, audit/notifications, staffing, task/project links, and complete rollback. Never loop over individual project/task RPCs.
- Invalidate proposal/project/work queries after confirmed success; open only authorized returned records.

**Tests/acceptance**

- Missing/stale approval, changed working snapshot, wrong owner, duplicate press/request, ambiguous timeout, rollback, invalid staffing, and denied participant.
- Demonstrate that mobile commit creates no budget commitments, allocations, or ledger records. No no-cost autofill or finance bypass is permitted to satisfy this gate.
- Verify created project/tasks enter the existing Phase 1/2 workflows with the same assignments and review routes as the approved draft.

### P3-FI-9 — Integrated acceptance and accurate completion records

- Run selected live workflows with real non-production recipient/member/reviewer/report/draft relationships.
- Exercise app launch, session restore, account switch, revoked access, offline/reconnect, background/resume, process death, invalid tokens, expired URLs, gateway rotation, AI outage, and upload/commit ambiguity.
- Inspect native layouts and long lists on representative Android/iOS sizes, dynamic text, contrast, keyboard/safe area, accessible action names, and disabled/error states.
- Keep Phase 1 evidence/submission/review and Phase 2 project lifecycle regressions in the suite.
- Update roadmap, parity matrix, contracts, and acceptance evidence per operation. Replace the adopted upstream baseline only after the required compatibility work is verified.

## 8. Module and route plan

Preserve existing modules and thin Expo Router files. These additions are planned paths, not currently implemented files:

| Area | Planned paths |
| --- | --- |
| Shared gates/jobs | `src/lib/phase-3/`, `src/contracts/ai-jobs.ts`, `src/lib/gateway/jobs/` |
| Existing Inbox | Extend `src/features/notifications/`; keep `src/app/(protected)/(tabs)/notifications.tsx` |
| Push | `src/features/push-notifications/`, including native adapter, registration, and response coordinator |
| Chat | `src/contracts/chat.ts`, `src/features/chat/`, `src/app/(protected)/messages/index.tsx`, `messages/[channel-id].tsx` |
| Briefs | `src/features/management-briefs/`; a protected contextual report route once Phase 2 report identifiers are fixed |
| Proposals | `src/contracts/proposal-import.ts`, `src/features/proposal-import/`, `src/app/(protected)/proposals/import.tsx`, `proposals/drafts/[draft-id].tsx`, `proposals/drafts/[draft-id]/review.tsx` |
| Entry points | Existing More, Settings, Task detail, Projects, and future Report detail |

Use existing components/tokens and consult the SDK 57 native UI guidance during implementation. Use virtualized lists for long feeds/history/hierarchies; do not restructure the app or add a sixth bottom tab.

Every remote key includes the current user and relevant environment/record/filter. Never put push tokens, message bodies, prompts, PDF text, or report data in query keys. Clear protected caches, subscriptions, pending response state, and resumable identifiers on sign-out/account switch; discard async results from an earlier session.

## 9. Test plan and required commands

Add or update meaningful tests in the same executable change. The following names are planned unless already present:

| Work | Test files / responsibilities |
| --- | --- |
| Existing Inbox | `src/features/notifications/api/notifications-api.test.ts`, `query-options.test.ts`, `navigation.test.ts`, `destinations.test.ts`, `screens/notification-list-screen.test.tsx` — recipient, unread/mark-all, errors, canonical lookup and routes |
| Gates | `src/lib/phase-3/capabilities.test.ts`, `permissions.test.ts` — fixture isolation, role/action denials |
| Push | `src/features/push-notifications/registration.test.ts`, `response-coordinator.test.ts`, `native-runtime.test.ts` — tokens, startup/module availability and session/navigation lifecycle |
| Chat | `src/features/chat/api/chat-api.test.ts`, `realtime.test.ts`, `screens/channel-screen.test.tsx`, `attachments.test.ts` — state, payloads, membership, message order and files |
| Jobs/briefs | `src/lib/gateway/jobs/state.test.ts`, `persistence.test.ts`, `use-job.test.tsx`, `src/features/management-briefs/api/brief-api.test.ts` — backoff/recovery/auth, advisory result |
| Proposal | `src/features/proposal-import/files/source-upload.test.ts`, `draft/validators.test.ts`, `draft/revisions.test.ts`, `api/commit.test.ts`, `screens/draft-review-screen.test.tsx` — privacy, conflicts and confirmed atomic results |
| Existing regressions | Preserve native tab cap, missing-picker runtime, safe UUID, gateway rotation, sign-out/cache cleanup, task review, evidence cleanup and project lifecycle tests |

Unit/component tests use controlled fakes. Real RLS/RPC/Storage/gateway/sender probes use an explicitly configured non-production environment, with named account relationships and sanitized results. Source analysis and mocked tests are not live policy proof.

Required commands during implementation:

- Targeted tests: `npm test -- --runTestsByPath <actual-test-file>`.
- After executable source or test changes: `npm run check`.
- After route/config/dependency/native/build changes: `npm run build:verify`.
- After confirmed database schema changes: `npm run supabase:types`, inspect generated diff, then checks.
- Rebuild/install the appropriate native client after adding native packages/configuration and test the installed artifact. On this Windows host, iOS device/build acceptance requires the team's suitable Apple/build environment; record it as pending if unavailable.

Do not carry the old Hermes export warning forward as a current failure without rerunning the relevant command and recording its current result. Historical export passes likewise do not establish device acceptance.

## 10. Delivery order and stopping rules

1. Record the P3-FI-0/P3-FI-1 implementation evidence and complete allowed/denied recipient probes before enabling any unverified Inbox capability.
2. Build push registration/response UI and integrate chat text only when each contract is ready; retain the development chat preview as a clearly non-live test tool.
3. Add chat edits/reactions/attachments individually with their own private data and permission evidence.
4. Connect the shared job foundation to brief/import development adapters, then integrate briefs when scoped reports and typed jobs exist.
5. Add proposal source processing, saved drafts, and review routing; keep the finance-sensitive commit gate isolated.
6. Integrate the approved atomic commit contract and finish end-to-end/device acceptance.

Each implementation handoff must say what is coded, what is enabled live, what was verified, and what remains. Include changed tests, commands/results, manual checks, and unrun checks with reasons. If one integration fails, report its exact operation and continue other authorized work. Do not end the whole implementation at the first missing push/AI contract.

## 11. Exit criteria

Phase 3 full integration is complete only when:

- [ ] Notifications have recipient-only reads/read updates, correct counts/filtering, stable pagination, safe destinations and Realtime behavior.
- [ ] Push registration, trusted delivery, preferences, receipts, token/account cleanup and foreground/background/cold-start behavior pass on Android/iOS.
- [ ] Standing chat has authorized history, send/read state, edits, reactions, private attachments, and revocation/reconnect behavior.
- [ ] Management briefs use real scoped reports and typed, authorized, recoverable jobs with clearly advisory results.
- [ ] Proposal source processing is private/server-side; saved drafts, concurrency, approval routing and explicit atomic commit satisfy the actual contract.
- [ ] Proposal commits comply with the Phase 4 finance exclusion; draft-only/web-handoff behavior remains labeled partial until this is resolved.
- [ ] Each sensitive operation passes at least one allowed and one denied identity case, plus its relevant inactive/revoked/cross-scope cases.
- [ ] Core work continues through AI/push outages and no sensitive operation is silently replayed offline.
- [ ] Applicable targeted/full checks, native exports, and device acceptance are recorded honestly.
- [ ] Documentation and parity reflect evidence rather than merely enabled flags or seeded test records.

## 12. Verification record

Tests added or updated: `src/lib/phase-3/capabilities.test.ts`, `src/features/notifications/api/notifications-api.test.ts`, `src/features/notifications/query-options.test.ts`, `src/features/notifications/screens/notification-list-screen.test.tsx`, `src/contracts/chat.test.ts`, `src/features/chat/development-fixtures.test.ts`, `src/features/chat/screens/channel-list-screen.test.tsx`, `src/features/chat/screens/channel-screen.test.tsx`, `src/contracts/ai-jobs.test.ts`, and `src/lib/gateway/jobs/persistence.test.ts`.

Validation for this implementation: repository instructions and full roadmap read; mobile source/configuration inspected at `3921e63`; remote web `main` compared with the recorded baseline and relevant files read at `042e1a5`; SDK 57 push documentation checked; targeted tests and `npm run check` passed (66 suites / 202 tests); `npm run build:verify` exported Android and iOS Hermes bundles; local Markdown links, pinned source paths, referenced package scripts, and `git diff --check` verified.

No migration, live backend mutation/probe, push delivery, production Storage action, Android/iOS device test, or financial action is claimed by this implementation.
