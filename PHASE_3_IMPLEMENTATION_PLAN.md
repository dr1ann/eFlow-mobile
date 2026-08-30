# Phase 3 Implementation Plan — Communication, Briefs, and Proposal Import

## Plan status

- Status: P3.0 contract ledger and a P3.2 read-only notification-inbox slice are implemented; Phase 3 is not complete
- Current repository phase: Phase 0 foundation plus partial Phase 1 task/evidence-preview and partial Phase 2 project-read slices; Phase 1 and Phase 2 are not complete
- Mobile repository baseline inspected: `381b27942b7dfe45fedc098c6acc76594d4661d8`
- Mobile stack: Expo SDK 57, React Native, TypeScript, Expo Router, Supabase, and TanStack Query
- Source roadmap: `MOBILE_IMPLEMENTATION_PHASES.md`
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest upstream `main` inspected: `7b072123a20876940be84217dbb6af3ad8d2700f` (not yet adopted as the mobile baseline)
- Migration reference inspected: `Migrations-20260827T143023Z-1-001/Migrations/`
- Plan created: August 30, 2026; scope revised August 30, 2026

Budget and petty-cash workflows are not part of Phase 3. They are deferred to Phase 4 or later because the current web implementation and its deployed schema, RLS, RPC, Storage, lifecycle, and role behavior are not stable enough to serve as an authoritative mobile contract. They do not contribute to Phase 3 implementation or completion.

Phase 3 is still a candidate portfolio, not authorization to copy every advanced web screen. Each selected feature must prove mobile value, a production-backed server contract, exact role behavior, and a safe native interaction. Phase 1 and Phase 2 release gates remain prerequisites for an integrated Phase 3 release because push destinations, chat membership, management briefs, and proposal import depend on the earlier notification, task, project, report, role, and authorization foundations.

Contract discovery and isolated read-only work may advance before those releases, but no Phase 3 mutation may use mock data, direct insecure table writes, client-controlled authorization, or a service-role credential. A partial screen must state its boundary honestly and must not be counted as a completed workflow.

### Current implementation boundary — August 30, 2026

The mobile client now has a paged, read-only Inbox tab. Its Supabase reads are explicitly scoped to the resolved profile ID and remain subject to RLS; only a minimal non-financial projection is requested. Supported task/project notifications use existing guarded UUID detail routes and receive a fresh destination read after navigation. Unknown notification types are deliberately generic and non-navigable so unsupported finance or future workflows do not expose content or create accidental scope.

Read-state mutations, unread counts, Realtime, push, chat, AI briefs, proposal import, and all other Phase 3 advanced work remain disabled or blocked. The detailed evidence and required identity probes are in `docs/PHASE_3_CONTRACTS.md`.

## Outcome

The first complete Phase 3 workflow will add trustworthy background notification delivery to the canonical Phase 1 in-app notification flow:

```text
Authorized business event creates a canonical in-app notification
  -> trusted server evaluates recipient preferences and registered devices
  -> server sends one minimal allowlisted push event
  -> Android or iOS displays the notification
  -> user taps it from foreground, background, or terminated state
  -> app restores or requests the signed-in session
  -> app loads the canonical notification for the current user
  -> guarded navigation re-checks the destination through RLS/RPC
  -> unauthorized, deleted, or malformed destinations fail safely
```

After push is secure and accepted, Phase 3 may deliver the remaining independent slices:

```text
Authorized channel member
  -> paged standing organization/task chat
  -> send, read, and receive active-app updates
  -> add edit/reaction/attachment behavior only through verified server contracts

Department Head
  -> requests a typed management-brief job from an authorized report
  -> resumes queued processing after navigation or restart
  -> reads verified observations separately from advisory recommendations

Authorized planner
  -> selects and privately uploads a PDF
  -> server extracts and decomposes it through a typed queued job
  -> user edits a collaboration draft
  -> required reviewers approve the exact revision
  -> owner explicitly commits the approved hierarchy atomically
```

Ordinary Supabase-backed work must remain usable when push delivery, the gateway, or the AI host is unavailable. AI output remains advisory. Push payloads do not become authorization. Proposal commits remain explicit, server-authorized, online-only operations.

## Scope and product decisions

1. **Finish the core before release.** Phase 3 acceptance requires the applicable Phase 0, Phase 1, and Phase 2 exit criteria. Phase 3 work must not hide the current evidence Storage, deployed RLS/RPC, project-mutation, reporting, Realtime, or device-acceptance gaps.
2. **Exclude unstable finance work.** Budget and petty cash move to Phase 4 or later. Do not add their routes, contracts, permissions, screens, tests, or completion requirements during Phase 3.
3. **Implement candidates independently.** Push, chat, AI briefs, proposal import, templates, performance views, collaboration, and export are separate release decisions. Completion of one does not require enabling all others.
4. **Push is the first vertical slice.** It has direct mobile value, but it starts only after the canonical Phase 1 in-app notification and guarded destination contracts are working.
5. **Push is server-originated.** The phone may register its own token and preferences. It may not choose arbitrary recipients or ask the server to send arbitrary notification content.
6. **Push does not replace in-app notifications.** The `notifications` row remains the canonical inbox item. A push carries a minimal event reference, then the app loads the authorized destination after sign-in and access checks.
7. **Chat scope is standing organization and task channels.** Direct messaging, broad directory discovery, moderation administration, retention controls, and audio/video calling require separate decisions. Calls remain deferred.
8. **Do not reuse unsafe chat writes.** The current web service directly inserts client-supplied sender IDs/names, writes reactions inside message-content JSON, creates mention notifications client-side, and uses admin routes for edits/deletes. Mobile waits for participant-scoped server mutations.
9. **Ship text-first chat.** Paged history, send, read state, and Realtime are the first chat slice. Editing, deletion, replies, mentions, reactions, and attachments remain disabled until each has a first-class server contract.
10. **AI briefs use typed jobs.** The client cannot select the model, build an arbitrary prompt, send private manager notes, or download excessive report data. The server owns authorization, context assembly, model policy, limits, audit, and job ownership.
11. **Proposal PDFs are processed on the server.** Mobile selects and uploads a validated PDF to private draft-scoped Storage. It does not port `pdfjs-dist`, parse the document on-device, or log extracted text.
12. **Proposal output is a draft.** AI decomposition, staffing, dates, and hierarchy are editable recommendations. Any operational financial fields remain omitted or unresolved until the future finance phase. The draft requires collaboration review and explicit approval before an approved atomic commit creates operational records.
13. **No partial client-side import commit.** Do not copy the web path that loops through separate project/task creates and can report mixed success. The final commit must be one authorized, idempotent or duplicate-safe server transaction.
14. **Other candidates need mini-plans.** Work templates, productivity/performance, interdepartment governance, and native report export/sharing begin only after their mobile journey, role matrix, minimal data contract, and ownership are approved.
15. **Use native mobile interaction patterns.** Keep primary navigation compact, use contextual routes, virtualize unbounded data, use native sheets/pickers/forms where supported, and do not copy desktop tables, PDF previews, chat drawers, or hierarchy canvases.

## Dependencies and readiness gate

Phase 3 contract work may begin in small increments, but an integrated release requires all applicable items below:

- [ ] Phase 0 Android and iOS device acceptance is complete.
- [ ] Phase 1 in-app notifications, evidence/submission/review, comments, Realtime, and deployed authorization tests pass.
- [ ] Phase 2 project/task/report and queued-job foundations required by the selected Phase 3 feature pass.
- [ ] The selected non-production Supabase project has auditable migration history matching the schema under test.
- [ ] Generated database types are regenerated after every confirmed schema change and match the non-production project.
- [ ] Active employee, Task Lead, Department Head, chat participant, unrelated-organization user, inactive user, Assistant Head, and Super Admin test identities are available as applicable.
- [ ] Exact permissions and persisted roles for every Phase 3 read and mutation are approved; client navigation permissions match but never replace the server rule.
- [ ] The current Super Admin all-permissions shortcut is reconciled with server-side operational mutation denies before Phase 3 actions are exposed.
- [ ] The Assistant Head scope decision is recorded for chat, briefs, collaboration drafts, and proposal approval; unresolved behavior fails closed.
- [ ] Push provider ownership is approved, the Expo project is linked, Android FCM and iOS APNs credentials are owned by the team, and no credential enters the mobile bundle.
- [ ] A user/device token-registration contract, server-only sender, delivery outbox, receipt handling, preference rules, and destination schema are deployed before push UI is enabled.
- [ ] Base chat table DDL, RLS, grants, Realtime publication, retention, membership, unread, edit/delete, reaction, mention, and attachment contracts are present in reviewed migrations for whichever capabilities are selected.
- [ ] Typed management-brief endpoints and a stable Phase 2 report contract are deployed before AI brief UI is enabled.
- [ ] Proposal upload, extraction/OCR, decomposition, job status, draft validation, collaboration review, and atomic commit contracts are deployed before PDF import UI is enabled.
- [ ] Realtime publication and RLS are verified for each subscribed Phase 3 table; Realtime remains an invalidation signal, not an authorization source.

If a dependency is unavailable, stop at the nearest truthful boundary: verified contracts, pure validators, a safe read-only screen, or a disabled action with a concrete explanation. Do not build a mock workflow and label it implemented.

## Upstream and contract assessment

### Upstream drift

The remote web `main` remains `7b072123a20876940be84217dbb6af3ad8d2700f`. In the inspected remaining Phase 3 paths, the diff from `508aabc` adds or changes proposal-import presentation components but does not add a Supabase migration or change the checked FastAPI AI/notification router source. This is UI/product evidence, not proof of a new deployed backend contract. The recorded mobile baseline remains `508aabc` until the full upstream compatibility review and mobile validation are complete.

| Classification | Observation | Phase 3 response |
| --- | --- | --- |
| Missing push contract | No Expo/device push-token table or trusted push sender was found. The server router sends authenticated email only. | Design and deploy device registration, event outbox/sender, receipt cleanup, and minimal destination payloads first. |
| Chat audit gap | Generated types contain `chat_channels`, `chat_channel_members`, and `chat_messages`, but the supplied migration archive contains synchronization fixes rather than the base chat DDL/RLS/grants. | Recover or create reviewed canonical chat migrations and run participant/nonparticipant probes before mobile reads or writes. |
| Unsafe web chat behavior | Web chat performs direct client inserts with client-supplied sender data, client-side mentions/notifications, JSON-encoded reactions, and admin-route edits/deletes. | Replace with authenticated participant-scoped RPC/server contracts that derive actor identity and enforce edit/moderation rules. |
| Unsafe generic AI | The gateway exposes generic `/ai/jobs` and `/ai/chat`; clients can supply model, messages, and large prompt content. The web brief builds the prompt client-side. | Add narrow versioned business endpoints with server-owned context, fixed model policy, structured results, limits, ownership, and audit. |
| Proposal foundation available | Migrations provide private `proposal-drafts` Storage, collaboration draft/revision/review RPCs, and atomic `commit_collaboration_draft`. | Verify deployed RLS/Storage/RPC behavior, then build mobile around this collaboration lifecycle. |
| Unsafe web import behavior | The web imports `pdfjs-dist`, builds AI prompts with personnel context on the client, logs raw model/employee details, and has a separate per-project/per-task commit path. | Use server extraction/decomposition, no sensitive logging, and one reviewed atomic collaboration commit. |
| Explicitly deferred | The user has removed budget and petty cash from Phase 3 because the web workflow is not stable. | Reassess only in a Phase 4+ audit and plan; do not create Phase 3 implementation dependencies. |
| Other deferred behavior | Audio/video calls and desktop-heavy governance, audit, and report workspaces remain technically complex or low-frequency on phone. | Keep them outside this plan unless an explicit product decision creates a separate evaluated slice. |

### Current source-contract inventory

The migration archive and generated types are source references; the deployed non-production project remains authoritative.

| Capability | Current reference | Required verification or change |
| --- | --- | --- |
| In-app notification | Generated `notifications` row, current notification mapping/navigation foundations, and Supabase Realtime | Complete Phase 1 inbox/read-state/destination contracts and prove recipient-only RLS before adding push. |
| Push registration | No reviewed contract found | Add owner-scoped device registration/revocation and server-only token reads/sends. |
| Push delivery | No trusted sender/outbox found | Add event allowlist, preference evaluation, deduplication, retry/receipt handling, token invalidation, and redacted payload policy. |
| Chat | Generated channel/member/message rows; task-channel synchronization fixes; web direct writes | Recover base DDL/RLS and replace writes with server-derived actor RPCs. Add first-class reactions/attachments or explicitly reduce scope. |
| Management brief | Generic queued AI proxy and client-built prompt | Add typed create/status/cancel brief jobs with server-owned report context and structured observation/recommendation output. |
| Proposal draft | `create_collaboration_draft`, revision/autosave, organization/review/change-request RPCs, private draft Storage | Verify participant/manager scope, source-file lifecycle, snapshot limits/version, stale revision behavior, and sign-out/privacy cleanup. |
| Proposal commit | `commit_collaboration_draft(draft, revision)` | Verify approvals, readiness, latest revision, duplicate commit, participant scope, project/task creation, audit/notification, and full rollback. Exclude unstable financial creation. |

## Product and backend decisions to record in `docs/PHASE_3_CONTRACTS.md`

P3.0 creates the contract ledger and records these decisions before the affected feature is enabled:

- Which remaining Phase 3 candidates are required for the capstone and which remain deferred.
- Whether an Assistant Head can use chat, request briefs, manage collaboration drafts, participate in approval, or commit proposals.
- Whether Super Admin receives oversight reads only or any explicitly audited operational action; default to operational mutation denial.
- The push provider (Expo Push Service or approved direct APNs/FCM infrastructure), infrastructure owner, credential owner, event allowlist, lock-screen privacy level, retention, and support process.
- The moment notification permission is requested and how a user can defer, revoke, or register another device.
- Chat channel membership, history retention, message size, edit/delete window, moderator role, mention syntax, reaction model, attachment limits, and whether organization-channel unread state is required.
- AI brief report types, permitted roles, maximum data scope, result schema, expiry, cancellation, rate limit, audit visibility, and whether deterministic fallback exists.
- Proposal PDF size/page/type limits, OCR support, retention, malware/content scanning, extraction timeout, job expiry, editable fields, approval path, and atomic commit ownership.
- How proposal import represents omitted or unresolved financial fields until the future Phase 4+ contract exists.
- Whether native report sharing, templates, performance views, or interdepartment collaboration add enough mobile value for a separate work package.

## Authorization targets

This table describes required server checks for integration testing. It does not grant permission and must be replaced with the approved deployed contract.

| Action | Intended actor and record scope | Required denials |
| --- | --- | --- |
| Read canonical notification | Authenticated recipient of that exact notification | Another user, inactive/missing profile, malformed ID, deleted/expired record |
| Register push token | Authenticated user registering the current installation for the configured app/environment | Supplying another user ID, cross-environment token, malformed token, inactive profile |
| Send push | Trusted server processing an allowlisted business event | Any mobile/client request that chooses recipient/title/body, unapproved event, muted preference |
| Open push destination | Recipient whose current role/RLS still authorizes the target | Cached permission only, revoked access, deleted target, forged destination kind/ID |
| Read/send chat | Current member or organization/task participant authorized for that exact channel | Guessed channel ID, removed member, unrelated org/task, client-supplied sender identity |
| Edit/delete/react | Message author within approved rule or explicit moderator; reaction actor derived from JWT | Editing another user's message, JSON sender/reaction spoofing, expired edit window, client-only moderation |
| Request management brief | Approved report viewer for the exact report scope | Employee/unrelated org, arbitrary prompt/model, another user's job, private manager-note upload |
| Read brief job/result | Job owner or explicitly approved same-scope viewer | Guessed job ID, account/environment mismatch, revoked report permission, expired job |
| Create/import proposal draft | Approved planner for the owner organization and collaboration scope | Employee without create permission, unrelated org, inactive user, unsupported role, unsafe file |
| Edit/review proposal draft | Server-authorized owner/participant for that exact revision and action | Role label alone, removed participant, stale revision, self-approval where prohibited |
| Commit proposal | Approved owner-side actor after required organizations approve the exact current revision | Participant without commit authority, stale/unapproved revision, duplicate commit, AI-triggered automatic commit |

Every protected route must bootstrap the current access snapshot, then perform a fresh RLS/RPC-backed record read. Sign-out, profile deactivation, permission revocation, or account switching must remove protected cached data, subscriptions, job IDs, notification destinations, and installation ownership as required by the contract.

## Lifecycle and data contracts

### Push event envelope

Use a versioned, minimal payload containing only an event ID or notification ID, destination kind, destination UUID, and schema version. Do not place private feedback, manager notes, report rows, chat bodies, proposal text, access tokens, or raw signed URLs in push payloads.

On notification response:

1. Restore or require the signed-in session.
2. Fetch the canonical notification/event using the current user.
3. Map only allowlisted destination kinds through a tested navigator.
4. Re-read the target through RLS/RPC.
5. Show the same unavailable state for unauthorized, deleted, malformed, or expired destinations.

### Chat model

Do not overload `chat_messages.content` with mutable reply/reaction metadata. Freeze a versioned server model for:

- Channel kind, organization/task relationship, membership, and membership version.
- Message body, author derived from authentication, creation/edit/deletion timestamps, and reply target.
- Reactions keyed by user identity with uniqueness and toggle semantics.
- Read cursor/unread count with server timestamps.
- Private attachment metadata and authorized object path.
- Edit/delete/moderation audit fields and retention behavior.

If the backend does not add first-class reaction/attachment/edit contracts, reduce the first chat slice to paged text history, send, and read state rather than encoding new behavior inside message text.

### AI management brief result

Prefer a structured result over one opaque text field:

- Verified observations, each tied to a server-known report row or metric reference.
- Recommendations clearly labeled as advisory.
- Report definition/version, data cutoff/freshness, generated timestamp, and safe scope label.
- Job state: at least queued, running, succeeded, failed, expired, cancelled, and unavailable, mapped from the approved gateway contract.
- No raw prompt, model chain-of-thought, private manager note, or unrelated personnel row.

### Proposal draft and commit

The import lifecycle should be:

```text
local PDF selected and validated
  -> authorized collaboration draft created
  -> PDF uploaded to {draft-id}/... in private Storage
  -> source metadata/hash attached through approved RPC
  -> typed extraction/decomposition job created
  -> job ID persisted and resumed safely
  -> structured hierarchy validated and repaired server-side
  -> editable revision saved with financial fields omitted/unresolved
  -> collaboration scope reviewed
  -> required organization approvals recorded against a revision
  -> current revision explicitly committed atomically
```

The commit input must exclude server-owned IDs, audit actors, approval claims, model names, arbitrary prompt text, hidden scoring context, and unstable financial allocations. A successful commit returns stable project/task references. Failure returns no partial operational hierarchy.

## Target navigation

Do not create one primary tab per advanced feature. Preserve a compact tab bar and add contextual entry points under existing Work, Projects/Manage, Inbox, and Settings surfaces.

Routes remain thin adapters under `src/app/`; screens, contracts, API code, and state live in feature modules.

```text
src/app/(protected)/
  notifications/index.tsx             Canonical in-app inbox
  messages/
    index.tsx                         Virtualized channel list
    [channel-id].tsx                  Paged message history
  reports/[report-id]/brief.tsx       Typed queued brief and advisory result
  proposals/
    import.tsx                        PDF selection and upload
    drafts/[draft-id].tsx             Editable versioned draft
    drafts/[draft-id]/review.tsx      Collaboration readiness/approval
```

All dynamic parameters use validated UUID parsing. Direct links to chat, report, job, proposal, notification, task, subtask, or project records must pass the exact permission and record-level server read before rendering details.

## Target module boundaries

Extend the existing feature-oriented structure without placing components or business logic inside route files:

```text
src/
  contracts/
    chat.ts
    push-notifications.ts
    ai-jobs.ts
    proposal-import.ts
  features/
    notifications/
      api/
      screens/
      navigation.ts
    push-notifications/
      api/
      lifecycle/
      navigation.ts
    chat/
      api/
      components/
      screens/
      realtime.ts
    management-briefs/
      api/
      persistence/
      screens/
    proposal-import/
      api/
      components/
      screens/
      draft/
      files/
  lib/
    files/
    gateway/
    query/
    supabase/
```

Use the existing `expo-document-picker` only through tested file abstractions. Use `@expo/ui` for supported short forms, pickers, menus, and sheets on SDK 57; use `FlatList` or `SectionList` for long notification, channel, message, and draft lists.

Push implementation will require `expo-notifications` and build-time notification configuration after the backend/provider decision. `expo-constants` is already installed; `app.json` currently has no `extra.eas.projectId`. Follow the [Expo SDK 57 notifications reference](https://docs.expo.dev/versions/v57.0.0/sdk/notifications/) and [push setup guide](https://docs.expo.dev/push-notifications/push-notifications-setup/). Push notifications require a development build rather than Expo Go, plus configured Android/iOS credentials. Do not add the dependency or credentials during contract-only work.

## Query, mutation, Realtime, and persistence strategy

### Query keys

Extend `src/lib/query/keys.ts` with user/environment/scoped keys that never contain raw chat text, report contents, PDF text, manager notes, or push tokens. Candidate families include:

```text
notifications.feed(userId, filter, page)
chat.channels(userId, filter, page)
chat.messages(userId, channelId, page)
briefs.job(userId, environmentId, jobId)
proposals.draft(userId, draftId, revisionId)
proposals.job(userId, environmentId, jobId)
```

### Mutation rules

- Mark push registration ownership changes, chat writes, AI job creation/cancel, proposal upload, draft revision, approval, and commit as online-only unless the approved contract explicitly defines a safe retry.
- Use server-supported idempotency keys for AI job creation, uploads, and proposal commits where available.
- Disable duplicate presses and preserve recoverable form state without claiming success.
- Do not retry unsafe mutations after a timeout unless the idempotency contract makes the result queryable.
- Invalidate the narrow affected keys after success; re-fetch authoritative unread counts, memberships, job states, and revision readiness.
- On server conflict or stale version, preserve user input, fetch current state, and require a new explicit confirmation.

### Realtime

- Use Realtime as an active-app invalidation signal for canonical notifications, chat messages/reactions/read state, AI runtime/job metadata when published, and proposal revisions/readiness.
- Scope channels by authenticated user and relevant record. RLS still filters delivery.
- Deduplicate by stable ID/version, preserve paged-list ordering, and refresh after reconnect.
- Remove every channel on unmount, sign-out, permission revocation, and account/environment switch.
- Never use Realtime as background push delivery.

### Safe persistence and app lifecycle

- Persist only safe identifiers and resumable state: job ID, operation type, owning user/environment ID, draft ID, safe timestamps, and bounded non-sensitive form drafts if approved.
- Never persist access tokens outside the existing secure session adapter, raw AI prompts/results containing sensitive context, PDF text, document bytes, signed URLs, push credentials, manager notes, or broad report rows.
- On AppState resume, refresh stale safe reads and perform one bounded status check for active jobs.
- On sign-out or account/environment mismatch, clear protected query caches, subscriptions, pending job records, notification response state, and user-bound installation ownership.

## Work packages

### P3.0 — Phase gate, value selection, and contract ledger

**Current state — August 30, 2026**

- `docs/PHASE_3_CONTRACTS.md` records the rechecked upstream SHA, generated notification surface, implemented boundary, financial deferral, and outstanding server gates.
- No non-production RLS, Realtime, Storage, RPC, gateway, push, or device probe is complete; this work package remains partial.

**Implementation**

- Confirm which remaining Phase 3 candidates are required and rank them by mobile value.
- Create `docs/PHASE_3_CONTRACTS.md` with deployed SHAs, migration versions, endpoint/RPC signatures, roles, permissions, states, Storage paths, push event schema, AI jobs, and open decisions.
- Record budget and petty cash as Phase 4+ deferred work without defining Phase 3 implementation tasks for them.
- Complete the upstream compatibility classification before adopting a newer web baseline.
- Resolve Super Admin and Assistant Head behavior.
- Provision non-production identities and fixtures for each selected feature.
- Record every disabled boundary in the roadmap and parity matrix.

**Tests and acceptance**

- Documentation statements match reviewed migrations, generated types, server routes, app config, and the selected deployed environment.
- At least one allowed and one denied identity probe exists for every sensitive read/mutation before mobile UI enables it.
- Missing contracts remain blocked; no service-role or production credential is introduced.

### P3.1 — Shared advanced-workflow foundation

**Implementation**

- Add Phase 3 domain contracts, strict mappers, error mappings, capability selectors, query keys, and UUID route parsing.
- Extend the permission registry only with approved deployed permission strings; remove assumptions that grant operational actions to Super Admin.
- Add safe job-record persistence and private-file validation/path utilities only where selected workflows require them.
- Define minimal redacted logging and user-safe error presentation for chat, push, AI, and documents.

**Tests and acceptance**

- Tests cover canonical states, unknown values, malformed job/event/file values, permission aliases/denies, user/environment mismatch, corrupt persistence, and idempotency-key stability.
- Sensitive values do not appear in query keys, errors, logs, or persisted records.
- Existing Phase 0–2 tests continue to pass.

### P3.2 — Canonical notification inbox and guarded destinations

**Current state — August 30, 2026**

- Implemented: a paged, recipient-filtered read-only Inbox; strict source mapping; generic non-navigable handling for unknown types; and guarded task/project destinations that re-read the target under RLS.
- Still blocked: filters, read/unread mutations, unread counts, Realtime invalidation, direct notification routes/cold-start recovery, and the allowed/denied deployment probes listed below. This is a partial slice, not completion of P3.2.

**Implementation**

- Complete the Phase 1 in-app notification list, pagination, filters, unread state, mark-one/mark-all behavior, and Realtime invalidation.
- Freeze an allowlisted destination schema for tasks, subtasks, reviews, projects, reports, chat channels, proposal drafts, and other selected records.
- Resolve a notification to a route only after loading the current recipient's canonical row.
- Re-check target access on every press, direct link, permission refresh, and cold-start response.
- Use a non-enumerating unavailable state for unauthorized, deleted, expired, or malformed targets.

**Tests and acceptance**

- API/mapping tests cover exact selects, pagination, unread counts, duplicate events, unknown types, malformed IDs, and error mapping.
- Screen tests cover loading, empty, offline cached read, refresh, timeout, forbidden state, deleted row, mark-read failure, and accessibility.
- Navigation tests cover every allowlisted destination plus unauthorized, deleted, malformed, revoked, signed-out, and cross-account cases.
- Non-production tests prove recipient-only reads/updates and denied unrelated identities.

### P3.3 — Push registration, trusted delivery, and cold-start navigation

This package begins with backend/infrastructure work. Do not add a token-registration screen to a server that cannot securely own tokens and business events.

**Required backend contract**

- Owner-scoped registration/upsert, token rotation, disable/revoke, last-seen, environment/app identity, and sign-out/account-change behavior.
- Server-only read access to tokens and server-only send authority.
- Allowlisted business event to notification mapping, user preference evaluation, deduplication, quiet/privacy rules, retries, push receipts, and invalid-token cleanup.
- Minimal versioned destination payload referencing the canonical in-app notification.
- Push credentials/access token stored only in trusted infrastructure; enable provider-side push security where approved.

**Mobile implementation**

- After the user understands the value, request permission once at an appropriate moment and support “not now.”
- Configure Android notification channels and iOS behavior according to the approved event classes.
- Acquire the Expo push token with the configured Expo project ID, register it through the authenticated backend, and listen for token rotation.
- Handle foreground receipt and background/terminated responses without duplicating canonical unread state.
- Route through the Phase 3 notification mapper, then re-check destination authorization.
- Add notification preferences and registered-device management under Settings.

**Tests and acceptance**

- Tests cover permission granted/denied/undetermined, missing project ID, offline token acquisition, rotation, duplicate registration, inactive profile, sign-out/account switch, server failure, listener cleanup, and token redaction.
- Navigation tests cover valid, malformed, unauthorized, deleted, expired, cross-account, and duplicate notification responses.
- Backend tests cover allowlisted events, muted users, deduplication, retry/receipt mapping, invalid-token disablement, and inability for a mobile user to send arbitrary pushes.
- Manual acceptance covers foreground, background, and terminated delivery on Android and iOS development builds. Expo Go is not accepted for remote-push verification.

### P3.4 — Standing organization/task chat

This package begins with canonical chat migrations and server mutations. The current web direct-write behavior is not a mobile contract.

**Required backend contract**

- Reviewed base DDL/RLS/grants/publication for channels, members, messages, and read state.
- Membership derived from authoritative organization/task participation, with removal/revocation behavior.
- Server-derived sender identity and participant-scoped send/read RPCs or authenticated routes.
- Cursor pagination, stable ordering, message limits, retention, and server-created mention/notification side effects where selected.
- First-class reply/edit/delete/reaction/attachment contracts before those optional actions are enabled.

**Mobile implementation**

- Build a virtualized channel list for standing organization/task channels with unread state and safe empty/error/offline presentation.
- Build a paged message screen that maintains scroll position, loads older pages, deduplicates Realtime events, and refreshes on reconnect.
- Add text send and read state first.
- Add reply, edit, delete, reactions, mentions, and private attachments only when each approved first-class server contract exists.
- Block sends offline rather than silently queuing them.
- Navigate task channels to the existing guarded task route.

**Tests and acceptance**

- API/mapping tests cover pagination cursors, exact payloads, server actor derivation, empty/malformed content, maximum length, duplicates, ordering, and error redaction.
- Permission tests cover member/nonmember, removed member, unrelated org/task, inactive user, and forged sender attempts.
- Optional-action tests cover author/moderator rules and forged mention/reaction/attachment attempts only when those actions are enabled.
- Realtime tests cover duplicate/out-of-order events, filtered pages, reconnect, unmount, sign-out, and channel-membership revocation.
- Manual checks use large histories on both platforms and verify keyboard, scroll anchoring, screen-reader labels, attachment picking where enabled, and network interruption.

### P3.5 — Typed queued AI management briefs

**Required backend contract**

- A narrow versioned operation to create, read, and cancel a management-brief job.
- Supabase bearer authentication, exact report permission/org scope, owner-scoped job access, server-side report loading, fixed model policy, payload/output limits, rate/concurrency limits, timeouts, expiry, cancellation, and redacted audit.
- A structured result separating verified observations from advisory recommendations and identifying report definition/freshness.
- Idempotent job creation or a request key that makes timeout recovery safe.

**Mobile implementation**

- Request a brief from an already authorized Phase 2 report without sending a model, arbitrary prompt, private notes, or broad personnel rows.
- Persist only the job record described in the shared persistence rules.
- Resume with bounded backoff after navigation/restart and pause continuous polling when backgrounded or after a bounded window.
- Render all queued/running/succeeded/failed/expired/cancelled/unavailable states and a user-triggered refresh/retry.
- Present verified observations separately from recommendations; provide no direct approval, assignment, spending, or notification action.

**Tests and acceptance**

- Gateway tests cover bearer headers, endpoint rotation for safe status reads, timeout, cancellation, typed errors, rate limits, ownership, and all job states.
- Tests prove the client cannot select a model, inject a prompt, upload private notes, view another user's job, or convert output into an automatic mutation.
- Persistence tests cover restart, AppState, expired/corrupt/oversized state, user/environment mismatch, sign-out, and terminal cleanup.
- AI/gateway outage leaves reports and all non-AI workflows usable.

### P3.6 — Server-extracted proposal PDF, editable draft, review, and atomic commit

This package begins with the server extraction/decomposition contract. The browser `pdfjs-dist` path is not portable and the generic AI path is not sufficiently constrained.

**Required backend contract**

- Draft-first private upload with file limits, hash/deduplication, extraction/OCR, malware/content checks where required, timeout, cleanup, and authorization.
- Typed queued decomposition that takes draft/source references, not raw client prompts or model selection.
- Server-side assembly of authorized organization/staffing context; private notes never return to unauthorized clients.
- Versioned structured hierarchy with size/depth limits, validation/repair errors, explicit unknown/missing fields, and safe recommendations.
- Revision ownership, stale-write handling, collaboration participant selection, readiness, approvals/change requests, and atomic duplicate-safe commit.
- Operational financial fields excluded from mobile import until the future Phase 4+ contract explicitly defines them.

**Mobile implementation**

- Select one PDF, validate it locally, create the draft, upload to the approved draft path, then create the typed job.
- Show upload/extraction/decomposition progress without keeping the screen awake indefinitely.
- Persist safe draft/job identifiers and resume after navigation, app suspension, or restart.
- Present an editable native hierarchy using focused screens rather than a desktop tree or drag-and-drop canvas.
- Validate title, hierarchy depth, dates, organizations, staffing, reviewer rules, and task/subtask relationships before requesting review.
- Show AI recommendations as editable drafts and require explicit collaboration review and a separate final commit confirmation.
- Invoke only the verified atomic collaboration commit; refresh created project/task references after success.

**Tests and acceptance**

- File tests cover MIME/extension mismatch, exact size/page boundaries, image-only PDFs, extraction failure, corrupt/encrypted PDF, cancellation, upload cleanup, hash duplicate, and unauthorized source access.
- AI tests cover malformed/oversized hierarchy, invalid dates/relationships, unexpected financial content, partial result, repair failure, timeout, expiry, cancellation, outage, and sensitive logging prohibition.
- Draft tests cover autosave/revision conflicts, app restart, collaboration scope changes, approvals tied to revision, requested changes, removed participants, and stale readiness.
- Commit tests cover explicit confirmation, current-revision enforcement, missing approval, unauthorized actor, duplicate press/commit, server rollback, notification/audit side effects, and no partial project/task hierarchy.
- Manual Android/iOS checks cover PDF selection, long editable drafts, keyboard/safe areas, background/resume, process restart, and accessible review/confirmation.

### P3.7 — Separately approved optional candidates and integrated acceptance

Do not implement optional candidates as a catch-all package. For each approved candidate, create a short contract addendum and one vertical workflow:

- Work-template discovery and authorized instantiation, building on the inspected template migration rather than desktop editing.
- Productivity/performance read-only views from permission-scoped snapshots; no client-built personnel scoring.
- Interdepartment collaboration/governance actions using existing draft/review RPCs, without reproducing the full desktop governance workspace.
- Native report export/sharing through a server-generated private artifact and platform share sheet; no browser print window or on-device PDF generation from sensitive raw datasets.

After selected slices are implemented:

- Run every selected workflow end to end against the shared non-production backend with realistic roles and data.
- Exercise permission revocation, stale sessions, offline transitions, app suspension, process restart, token rotation, Realtime reconnect, push duplicates, AI outage, interrupted uploads, and stale proposal state.
- Audit logs, errors, screenshots, query keys, persisted values, push payloads, signed URLs, and analytics for sensitive information.
- Verify accessibility, dynamic text, contrast, touch targets, keyboard handling, safe areas, long-list performance, and platform lifecycle behavior.
- Update the roadmap, parity matrix, contract notes, and upstream baseline only when evidence supports the new status.

**Tests and acceptance**

- Targeted tests pass during development.
- `npm run check` passes after every executable/test/config batch and at final integration.
- `npm run build:verify` passes after route, Expo config, dependency, asset, notification, or native integration changes and at final release acceptance.
- Android and iOS manual acceptance passes for both successful and denied workflows.
- Backend-blocked or unselected candidates remain visibly unavailable and are not counted toward Phase 3 completion.

## Test inventory

Final filenames follow the established feature layout; do not create placeholder tests. At minimum, plan for these responsibilities:

| Area | Expected automated coverage |
| --- | --- |
| Roles/permissions | Every approved actor, unknown/inactive roles, Assistant Head decision, Super Admin denies, revoked permissions, direct deep links |
| Notification inbox | Recipient scope, mapping, pagination, unread state, deduplication, malformed/deleted destinations, Realtime cleanup |
| Push registration | Permission states, project ID, token rotation/upsert/revoke, account switch, inactive profile, error redaction, listener cleanup |
| Push delivery/navigation | Event allowlist, preferences, dedupe, receipts, invalid token, foreground/background/cold start, malformed/unauthorized destination |
| Chat | Channel scope, pagination/order, send/read payloads, actor spoof denial, unread state, membership revocation, Realtime cleanup |
| Optional chat actions | Edit/delete/reply/reaction/mention/attachment authorization and validation only for enabled first-class contracts |
| AI briefs | Auth, typed request, job states, timeout/cancel/backoff, persistence/recovery, private-data omission, observation/recommendation separation |
| Proposal files/jobs | PDF validation/upload/cleanup, extraction/OCR errors, typed job lifecycle, privacy, restart/resume, malformed decomposition |
| Proposal drafts/commit | Revision conflicts, validation/repair, participant scope, approvals, explicit confirmation, duplicate commit, atomic rollback |
| Offline/lifecycle | Safe cached reads, no chat/proposal mutation replay, AppState, restart, reconnect, sign-out cleanup, user/environment mismatch |
| Navigation/accessibility | UUID routes, access bootstrap, permission-gated entries, important labels/actions, keyboard/error/disabled states |

Likely colocated files include `src/features/notifications/api/notifications-api.test.ts`, `src/features/notifications/navigation.test.ts`, `src/features/push-notifications/lifecycle/registration.test.ts`, `src/features/chat/api/chat-api.test.ts`, `src/features/chat/screens/channel-screen.test.tsx`, `src/features/management-briefs/persistence/job-record.test.ts`, and `src/features/proposal-import/draft/validators.test.ts`. Use the actual names selected during implementation.

Automated unit tests use mocks. RLS, RPC, Storage, push sender, Realtime, and gateway integration tests use only the explicitly configured non-production environment, never production.

## Non-production integration matrix

At minimum, selected workflows must prove:

- Notification recipients can read/update only their own canonical rows.
- Push registration derives the user from the bearer token and a client cannot send arbitrary notifications.
- Push responses cannot bypass current target authorization or reveal deleted/hidden record existence.
- Chat participants can read/send only in current channels; removed/unrelated users receive no rows or Realtime events.
- Chat sender identity comes from the server, not client fields.
- Brief requesters see only their authorized jobs and approved report scope.
- Proposal owners/participants see only permitted drafts/files/revisions and only the approved owner actor can commit.
- Proposal import cannot introduce operational financial data while that contract remains deferred.
- Assistant Head and Super Admin behavior matches the recorded decision.
- Inactive, missing-profile, malformed-role, stale-session, and unrelated-organization identities are denied.
- Required audit/notification side effects are atomic with the business mutation.
- Failed upload/metadata/commit work leaves no unauthorized or orphaned object/record presented as success.

## Manual Android and iOS checklist

- [ ] Cold sign-in/session restore reaches only permission-gated Phase 3 entry points.
- [ ] Direct links to unauthorized, deleted, expired, archived, malformed, and unrelated records fail safely.
- [ ] Notification, channel, message, report, and proposal lists virtualize and scroll smoothly with realistic data.
- [ ] Airplane mode permits only approved cached reads and blocks chat, AI, upload, approval, and commit mutations.
- [ ] Reconnect refreshes unread counts, messages, jobs, and revisions without duplicates.
- [ ] App background/resume and process restart recover safe job/draft state and do not replay sensitive mutations.
- [ ] Push permission can be deferred; token registration/rotation and Settings preferences work without exposing the token.
- [ ] Foreground, background, and terminated push delivery/deep linking work in Android and iOS development builds.
- [ ] Chat keyboard, long history, older-page loading, scroll anchoring, optional actions, and membership revocation work.
- [ ] AI/gateway outage does not block notifications, chat, reports, tasks, projects, or reviews.
- [ ] Proposal PDF selection, permission denial, large/corrupt files, cancellation, interrupted upload, cleanup, and private access work.
- [ ] Proposal upload/decomposition survives navigation and restart; long drafts remain editable and final commit is unmistakably explicit.
- [ ] Sign-out/account switch removes protected caches, subscriptions, jobs, pending notification responses, and user-bound installation state.
- [ ] Light/dark mode, contrast, screen-reader labels, dynamic text, touch targets, keyboard/safe areas, and platform-specific notification behavior are acceptable.

## Implementation sequence

Implement in this order, stopping at every unresolved backend gate:

1. P3.0 — Confirm candidate value, finish prerequisite gates, freeze deployed contracts, roles, and infrastructure ownership.
2. P3.1 — Add only the shared contracts, validators, permission corrections, persistence, and file foundations required by selected workflows.
3. P3.2 — Complete the canonical notification inbox and guarded destination mapping.
4. P3.3 — Add trusted push registration/delivery and verify foreground, background, and terminated navigation.
5. P3.4 — Add text-first standing organization/task chat after canonical migrations and server mutations exist.
6. P3.5 — Add typed queued AI management briefs after Phase 2 reports and narrow endpoints exist.
7. P3.6 — Add server-extracted proposal import, editable collaboration revisions, approval, and atomic commit.
8. P3.7 — Plan only explicitly approved optional candidates, then run integrated security, lifecycle, device, and documentation acceptance.

Each package leaves the application truthful at its current boundary. A completed canonical notification inbox is acceptable before push. A polished chat reaction, push opt-in, AI brief, or PDF-import screen backed by an unsafe or missing contract is not.

## Phase 3 exit checklist

Phase 3 is complete only for the explicitly selected candidate set, and only when all applicable items are true:

- [ ] Phase 0, Phase 1, and Phase 2 prerequisites used by the selected workflows are complete.
- [ ] Budget and petty cash remain excluded and are not counted toward Phase 3 completion.
- [ ] Every selected feature has documented mobile value, roles, permissions, state machine, server contract, and ownership.
- [ ] Canonical in-app notifications are recipient-scoped, paged, deduplicated, and mapped only to guarded destinations.
- [ ] If push is selected, token registration and delivery are server-owned, preference-aware, receipt-cleaned, and verified in foreground/background/terminated states on both platforms.
- [ ] Push payloads are minimal and every destination is re-authorized before rendering.
- [ ] If chat is selected, base DDL/RLS is auditable, actor identity is server-derived, participant scope is enforced, history is paged, Realtime is cleaned up, and offline sends are blocked.
- [ ] Optional chat behavior exists only where first-class server contracts and matching tests exist.
- [ ] Audio/video calls remain deferred unless a separate native WebRTC evaluation and plan is approved.
- [ ] If AI briefs are selected, jobs are typed, owner-scoped, resumable, context/model policy is server-owned, and recommendations are clearly advisory.
- [ ] If proposal import is selected, PDFs remain private, extraction/decomposition is server-side, drafts survive app lifecycle safely, approvals bind to revisions, unstable financial fields are excluded, and final commit is explicit and atomic.
- [ ] AI or push outages do not block ordinary Supabase-backed work.
- [ ] Assistant Head, Super Admin, notification recipient, chat participant, report viewer, proposal owner/participant, inactive user, and unrelated user behavior matches approved contracts.
- [ ] Targeted tests, `npm run check`, and every applicable `npm run build:verify` pass.
- [ ] Selected backend integration suites and Android/iOS manual acceptance pass, or every limitation is explicitly documented.
- [ ] `MOBILE_IMPLEMENTATION_PHASES.md`, `docs/FEATURE_PARITY_MATRIX.md`, Phase 3 contract notes, and the adopted upstream baseline reflect verified reality.

## Primary risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Phase 3 distracts from incomplete core workflows | Keep Phase 1/2 release prerequisites explicit and implement Phase 3 only as independently gated vertical slices. |
| Deferred finance scope quietly returns through proposal import | Reject or preserve operational financial fields as unresolved draft data until a Phase 4+ contract and plan explicitly authorize them. |
| Client can send arbitrary push content or target another user | Accept only server-generated allowlisted events; tokens and sender credentials are server-owned. |
| Push exposes sensitive lock-screen content | Send minimal generic text/reference, honor preferences, and fetch authorized details only after app open. |
| Token remains attached to the wrong account/device | Use installation ownership, token rotation, account-switch/sign-out handling, last-seen/revoke controls, and receipt cleanup. |
| Chat base security cannot be audited | Recover/create canonical migrations and denied integration tests before enabling any channel read/write. |
| Chat actor/reaction/mention can be spoofed | Derive actor from JWT, store first-class reaction/mention data, and create notifications server-side. |
| Realtime duplicates or reorders messages/notification state | Use stable IDs/versions, paged deduplication, invalidation-first refresh, reconnect handling, and cleanup tests. |
| Generic AI endpoint leaks models, prompts, private notes, or report data | Use narrow typed jobs with server-owned context/model/limits and redacted audit; do not call generic endpoints. |
| AI output is mistaken for verified management fact | Return structured observations/recommendations with source references, freshness, and advisory labels. |
| Browser PDF logic or raw document text moves to mobile | Upload privately and extract/OCR on the server; persist only safe draft/job identifiers. |
| Proposal import partially creates projects/tasks | Use one reviewed current-revision atomic commit with duplicate/stale checks and rollback tests. |
| Sensitive values leak through logs, query keys, screenshots, or persistence | Define a redaction inventory, test safe persistence, inspect artifacts, and prohibit raw document/chat/AI content logs. |
| Native push/file behavior passes unit tests but fails on devices | Require development-build push tests and real Android/iOS picker, background, cold-start, and lifecycle acceptance. |
| Scope expands into calls, finance, or desktop governance | Require an explicit future-phase product decision and separate technical evaluation before adding deferred work. |

## Documentation verification for this plan

This change is documentation-only, so unit and runtime tests are not applicable. Verify the plan by checking `AGENTS.md`, `MOBILE_IMPLEMENTATION_PHASES.md`, the current mobile repository state, current Expo SDK/package/app configuration, existing Phase 1/2 plans and contract notes, generated database types, the supplied migration archive, the `508aabc..7b072123` upstream comparison, current FastAPI routes, referenced local paths, official Expo SDK 57 notification guidance, Markdown structure, and `git diff --check`.

Executable tests become mandatory when a work package changes TypeScript, tests, dependencies, routes, Expo configuration, native notification behavior, build scripts, Supabase contracts, or gateway integration.
