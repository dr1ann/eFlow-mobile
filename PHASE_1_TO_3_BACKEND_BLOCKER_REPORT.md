# eFlow Mobile Phases 1–3 — Development, Integration, and Release-Gate Report

- Prepared: August 31, 2026
- Audience: web/backend/Supabase owner and the teammate's implementation agent
- Mobile repository: `eFlow-mobile`
- Recorded mobile web baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest web `main` inspected: [`042e1a5b240cf667eb3dfa69d263897686de2a04`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/commit/042e1a5b240cf667eb3dfa69d263897686de2a04)
- Latest compared web range: [`7b072123...042e1a5b`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/7b072123a20876940be84217dbb6af3ad8d2700f...042e1a5b240cf667eb3dfa69d263897686de2a04)
- Configured mobile Supabase project reference: `ixnfphgjyelhckjwjkdv`

## Read this first

This report separates backend readiness from mobile implementation. A committed migration or web screen does not automatically complete a mobile phase. A backend capability is ready for mobile only after its deployed contract, authorization, failure behavior, and allowed/denied integration tests are verified in the shared non-production environment.

**Pending release verification is not a blanket instruction to stop developing.** Mobile implementation should continue wherever work can be isolated safely. This report uses three distinct classifications:

| Classification | Meaning | May mobile development continue? |
| --- | --- | --- |
| **Development work available** | Screens, navigation, forms, loading/error/offline states, pure contracts, validators, accessibility, and tests can be built without a live mutation | **Yes** |
| **Live-integration blocker** | A specific live read/mutation cannot be enabled because its authoritative server contract is missing, unsafe, or returns the wrong authorization result | **Yes for UI/mocks; no for claiming or enabling the live integration** |
| **Release-verification gate** | The implementation may exist, but a phase cannot be called complete until deployed allowed/denied, lifecycle, Realtime, failure, and device tests pass | **Yes** |

Do not describe a phase as generally “blocked” when only one live integration is blocked. Name the exact operation and continue unrelated implementation.

### Development work that should continue now

The mobile agent may continue building:

- Native screens, routes, forms, filters, virtualized lists, and interaction states.
- Pure types, strict mappers, validators, permission presentation, query keys, and error mappings.
- Loading, empty, permission-denied, offline, timeout, retry, cancellation, and recovery UI.
- Component/unit tests with controlled fakes.
- Development-only mocked workflows for unavailable contracts.
- Accessibility, safe-area, keyboard, responsive-layout, and native picker behavior.
- Independent authenticated reads already protected by deployed RLS.

Development-only mocks must be visibly and structurally isolated from production data access. They must not ship as live workflows, silently activate in a production build, or be reported as deployed/RLS-tested behavior.

### Operations that must not be bypassed

Continue development without weakening the security boundary. Do not:

- Disable or widen RLS to make a client call pass.
- Put a service-role key in mobile.
- Make a private bucket or protected table public.
- Let a role label replace record-level assignment, reviewer, participant, or organization checks.
- Treat a mocked success as a successful live mutation.
- Grant extra permissions to hide a broken cleanup, atomicity, routing, or lifecycle contract.

### Intended permission map

| Person | Intended authority |
| --- | --- |
| Assigned employee/contributor | Update and submit their assigned work |
| Effective Task Leader | Manage their task's subtasks and review when correctly routed |
| Assigned reviewer | Decide eligible submissions, but never their own |
| Authorized Head/Assistant Head | Manage work only within their authorized organization/project scope |
| Ordinary project member | Membership alone does not grant management |
| Super Admin | Operational projects are oversight/read-only |
| Unrelated or inactive account | No protected access |

These are relationship-based rules. Test accounts must prove the relevant database relationships; usernames and displayed role labels alone are insufficient.

The attached `20260831000001_task_evidence_security.sql` exactly matches the migration committed in the teammate's repository. Its SHA-256 is:

```text
38615808bf4cf6c7e6220ad4477d56155d5c25fedc0e2610823a8e4b5b184c4c
```

The teammate reports that this migration has already been applied. **Do not run it again merely for this handoff.** Verify its deployed definitions and behavior with read-only inspection and real-user API/RPC tests. The repository and attached handoff are evidence of source work, not by themselves a deployment receipt.

Budget, funding, petty-cash, cash-release, and receipt workflows remain deferred. The September 6 [capstone sequence](PHASE_4_TO_9_IMPLEMENTATION_PLAN.md) assigns Phases 4–9 to operational completion; finance has no assigned phase. The new cash-release work in web commit `042e1a5b` does not count toward Phase 1, Phase 2, or Phase 3 mobile completion.

## Executive verdict

| Phase | Current live boundary | Effect of latest web update | Work that can continue now |
| --- | --- | --- | --- |
| Phase 1 | Task/subtask reads and a local-only evidence picker are present; live workflow mutations are disabled | Adds a strong task-evidence security migration, validation rules, cleanup-claim RPC, and reviewer-precedence correction; deployment and live authorization acceptance remain open | Finish screens/forms/state handling with mocks; implement the documented claim-before-remove client helper; add tests and native UX |
| Phase 2 | Permission-gated project list/detail reads are present | Adds project readiness/completion/archive RPCs, but not the required live create/edit/report/AI contracts | Build project creation/edit/member/milestone/report UI against typed development fakes while the exact mutation contracts are hardened |
| Phase 3 | Recipient-filtered read-only Inbox and guarded task/project destinations are present | No live push, chat, typed AI brief, or server-side proposal-import infrastructure was added | Complete notification UI/read-state architecture and build chat/brief/proposal draft UX behind development-only adapters |

“Live boundary” means the point beyond which the app must not call or claim an unverified protected backend operation. It does not prohibit continuing isolated implementation beyond that boundary.

## Shared blockers affecting all three phases

### X-01 — Deployment history and contract traceability

**Severity:** Critical release gate  
**Owner:** Backend/Supabase owner
**Classification:** Release-verification gate; does not block unrelated UI, pure logic, mocks, or unit tests

The earlier mobile audit returned an empty linked migration list even though the deployed schema was populated. The new handoff also states that migration history was not reconciled. This makes it difficult to prove which functions, triggers, policies, publications, and Storage settings are actually active.

Required work:

1. Confirm that `ixnfphgjyelhckjwjkdv` is the agreed shared non-production project.
2. Record how its current schema was deployed.
3. Compare deployed definitions with committed migrations without resetting the database or blindly pushing all migrations.
4. Record each relevant migration filename, source commit, deployment time, and outcome.
5. Establish an auditable deployment process for future contract changes.

Required evidence:

- Project reference and environment name.
- Migration deployment record without credentials.
- Sanitized policy/function/trigger/publication inspection output.
- Explanation of any migration-history mismatch and how it was reconciled.

Do not use `db reset`, a broad `db push`, or migration-history repair until the live schema has been compared with source.

### X-02 — Real non-production authorization identities

**Severity:** Critical acceptance gate  
**Owner:** Backend owner/project administrator
**Classification:** Live-integration test dependency; does not block mocked workflow development

Provide securely managed test identities and records for:

- Assigned employee/contributor.
- Effective Task Lead.
- Department Head.
- Assistant Head if it is intended to be supported.
- Primary reviewer.
- Backup reviewer.
- Project member without management authority.
- Unrelated employee.
- Self-review collision.
- Inactive profile.
- Missing-profile or unsupported-role case.

Credentials must be transferred securely and must not appear in this report, source control, screenshots, logs, or agent prompts. Each identity must have real task/project/reviewer relationships; changing only the displayed role name is not an authorization test.

### X-03 — Generated types and versioned contract handoff

**Severity:** High  
**Owner:** Backend owner, then mobile owner
**Classification:** Live-integration dependency for changed RPCs/routes; documented placeholder types and fakes may be used for development

After deployed schema changes are confirmed:

1. Regenerate Supabase database types from the same non-production project.
2. Commit the backend-generated types or provide a reproducible generation command and schema version.
3. Document new/changed RPC names, arguments, result payloads, error codes, permissions, and idempotency behavior.
4. Version gateway request/response contracts and publish the corresponding OpenAPI or typed schema.
5. Call out breaking changes instead of requiring mobile to infer them from web UI code.

### X-04 — RLS and Realtime must be tested together

**Severity:** High  
**Owner:** Backend plus integration testing
**Classification:** Release-verification gate for each Realtime-backed workflow

For every table used as a Realtime invalidation source:

- Confirm it is intentionally included in the deployed publication.
- Confirm the same user can perform the corresponding authorized `SELECT`.
- Prove unrelated, inactive, and anonymous identities cannot receive protected rows or events.
- Test duplicate events, reconnect behavior, deletion, and permission revocation.

A table appearing in a migration or generated type is not proof of deployed Realtime behavior.

### X-05 — Record current backend/web validation accurately

**Severity:** Medium release-record item  
**Owner:** Web/backend owner
**Classification:** Release-verification evidence; not a mobile development blocker

The Phase 1 handoff records an earlier checkout where isolated PostgreSQL evidence-security tests passed while the full web checks failed because UI dependencies/types were unresolved. The teammate now reports that the latest local typecheck and build pass. Treat the older build warning as superseded for day-to-day development rather than as a reason to stop mobile work.

For the release record, provide the exact successful commands, commit SHA, and concise results. No GitHub Actions run was visible for commit `042e1a5b` during this audit, so the reported local pass is not independently represented by remote CI. CI remains recommended, not a prerequisite for writing unrelated mobile code.

Keep isolated SQL results, web unit/type/build results, deployed Supabase integration results, and native mobile/device results as separate evidence categories.

## Phase 1 — Employee-to-reviewer workflow blockers

**Development status:** Continue implementing Phase 1 screens, forms, state machines, error handling, cleanup-helper code, and tests. Keep live evidence upload/submission/review calls disabled until their specific deployed tests pass. The evidence contract is detailed enough to implement against a fake adapter now.

### What the latest migration appears to fix

The committed `20260831000001_task_evidence_security.sql`:

- Removes the broad `taskfiles_rw` policy and earlier hotfix policies.
- Keeps task evidence private and scopes access to task/subtask relationships.
- Validates the uploader, canonical task/subtask/submission path, stored object metadata, file type, file size, and file count.
- Requires evidence for subtask submissions while keeping parent-task evidence optional.
- Makes finalized evidence bindings/history immutable.
- Adds `get_task_evidence_rules()`.
- Adds `claim_task_evidence_cleanup(text,text)` and race-safe sealing/cleanup behavior.
- Prefers the actual `assigned_to` Task Lead over a stale `recommendation_lead_id`.
- Preserves the existing submission/progress RPC signatures and their audit/notification behavior.

This is a substantial source-level fix. It still requires the following work before Phase 1 mobile mutations are enabled.

### P1-B01 — Verify the deployed evidence migration without reapplying it

**Severity:** Critical  
**Owner:** Backend/Supabase owner
**Classification:** Release-verification gate for the live evidence integration

Perform read-only checks confirming:

- `taskfiles_rw` and superseded hotfix policies are absent.
- The new restrictive and operation-specific evidence policies exist.
- `get_task_evidence_rules()` exists with the agreed result.
- `claim_task_evidence_cleanup(text,text)` exists with the agreed grants.
- Evidence triggers and the private `eflow_evidence` schema objects exist.
- Existing task/subtask RPCs have the intended trigger protection.
- PostgREST schema cache has reloaded.

Required evidence:

- Sanitized policy names, commands, roles, and relevant predicates.
- Function signatures and grants.
- Trigger names and target tables.
- Migration filename, Git commit, project reference, and deployment time.

### P1-B02 — Finish Storage bucket configuration

**Severity:** Critical  
**Owner:** Backend/Storage owner
**Classification:** Live-integration configuration blocker for actual uploads; picker/form development may continue

The observed `task-attachments` bucket was private with a 50 MiB limit but had no MIME allowlist. Confirm or fix:

- Bucket remains private.
- Maximum object size is 50 MiB or lower.
- Storage MIME allowlist matches `get_task_evidence_rules()`.
- `task-files` is not created merely for compatibility; if it exists, it remains private and legacy-only.
- Signed links use a short agreed lifetime. The current handoff recommends 300 seconds.
- Signed URLs are never stored as canonical file paths.

SQL RLS cannot enforce the requested signed-URL lifetime. If a hard maximum is required, provide a trusted signer endpoint rather than allowing arbitrary client expiry values.

### P1-B03 — Complete real-user Storage and workflow tests

**Severity:** Critical  
**Owner:** Backend plus mobile/web integration testing
**Classification:** Release-verification gate; mock-based development may continue

Run against the actual Storage API and deployed RPCs with real user JWTs:

| Case | Required result |
| --- | --- |
| Assigned contributor uploads and saves progress | Allowed |
| Assigned contributor submits a subtask with valid evidence | Allowed and routed to the effective Task Lead |
| Effective Task Lead submits the parent after all subtasks are approved | Allowed |
| Unrelated, inactive, missing-profile, or anonymous actor accesses evidence | Denied |
| Stale `recommendation_lead_id` differs from `assigned_to` | Stale lead gains no authority |
| Forged task/subtask/attempt path, nonexistent object, or another uploader's object | Rejected atomically |
| Empty, oversized, unsupported, or eleventh file | Rejected |
| Submitted object overwrite, move, rebinding, or deletion | Denied |
| Wrong reviewer or self-review | Denied |
| Primary/backup reviewer according to the authoritative routing rule | Allowed only when eligible |
| Submission races cleanup | Exactly one operation wins; finalized evidence is never deleted |
| Response is lost after submission commit | Submission can be reconciled by its caller-generated UUID |

Administrative or service-role queries do not count as proof because they bypass RLS.

### P1-B04 — Update cleanup callers and provide orphan cleanup

**Severity:** Critical for failure atomicity  
**Owner:** Web/backend owner; mobile will implement the same contract afterward
**Classification:** Genuine live upload/cleanup integration blocker; both clients can implement the documented helper immediately

The latest web commit did not update the documented direct cleanup callers:

- `src/app/features/tasks/services/taskReviewLifecycleService.ts`
- `src/app/features/subtasks/services/subtaskWorkflowService.ts`

Required web change:

1. Call `claim_task_evidence_cleanup` first.
2. Only remove the exact object after the claim succeeds.
3. Never run claim and remove in parallel.
4. Retry removal at the same tombstoned path if deletion fails.
5. Reconcile a timed-out submission by its submission UUID before cleanup.
6. Do not hide the original workflow error behind a cleanup error.

Also provide a trusted scheduled worker for uploads abandoned by interrupted clients. It must use a conservative age limit, small batches, claim-before-remove, exact paths, retry/alert behavior, and server-only credentials. Never delete directly from `storage.objects`.

### P1-B05 — Verify the complete task/review authorization matrix

**Severity:** Critical  
**Owner:** Backend owner
**Classification:** Per-operation live-integration and release-verification gate; unrelated screens and mocked interactions may continue

Verify and document these deployed operations:

- `transition_task_status`
- `save_subtask_progress`
- `submit_subtask_for_review`
- `decide_subtask_review`
- `submit_task_for_review`
- `decide_task_review`
- Task Lead-only subtask create, assign, reorder, reschedule, delete, and rule changes
- Dependency/prerequisite enforcement
- Duplicate and stale-state rejection
- Primary/backup reviewer routing and self-review prevention
- Atomic audit and notification side effects

Client permissions are presentation guards only. Every allowed and denied action must be enforced by the deployed RPC/RLS contract.

### P1-B06 — Notifications, announcements, comments, and Realtime

**Severity:** High  
**Owner:** Backend owner
**Classification:** Live-integration gate for each listed communication capability, not for unrelated Phase 1 work

Provide and test:

- Recipient-only notification reads and read-state writes.
- Notification pagination, stable ordering, and deduplication contract.
- Announcement audience, organization scope, active/expiry rules, and acknowledgement behavior if applicable.
- Task-comment read/write scope for authorized participants only.
- Realtime publication and RLS behavior for tasks, subtasks, progress, submissions, attachments metadata, reviews, notifications, announcements, recipients, and comments.
- A two-client probe where mobile submission updates the correct web reviewer while an unrelated account receives neither the row nor event.

### Phase 1 backend-ready definition

Phase 1 is ready for the remaining mobile implementation only when:

- P1-B01 through P1-B06 have passed against the shared non-production project.
- Required test identities are available securely.
- Generated types contain the new evidence RPCs.
- Evidence path, validation, cleanup, signed-access, submission, and review contracts are frozen.
- No service-role credential or authorization bypass is required by mobile.

After that handoff, mobile still must implement progress writes, uploads, cleanup, submissions, reviewer decisions, communications, Realtime refresh, error recovery, and Android/iOS acceptance. The backend fix does not automatically complete the mobile UI.

## Phase 2 — Department operations, projects, reports, and operational AI blockers

Phase 2 depends on the Phase 1 security and identity gates. Contract design may proceed in parallel, but an integrated Phase 2 release cannot be accepted while its underlying task/review workflow is unverified.

**Development status:** Continue building project creation/edit/member/milestone/report screens, validation, loading/error states, permission presentation, and tests behind development-only repositories. Enable each live mutation only when that exact RPC and permission matrix are accepted. AI UI can use deterministic fake queued-job states until a typed endpoint exists.

### P2-B01 — Freeze the Department Head permission matrix

**Severity:** Critical  
**Owner:** Product/backend owner
**Classification:** Product/authorization decision for live operations; UI states for the intended map may be developed now

Document and enforce the exact effective permissions for:

- `dept_head` / `department_head`.
- `assistant_head` and whether it is supported for each operation.
- Employee/project member.
- Effective Task Lead.
- Resolved reviewer.
- Super Admin as oversight read-only versus operational mutations.
- Inactive, unrelated-organization, and out-of-subtree users.

Do not grant management authority from a display role or navigation permission alone. Each operation must combine the effective permission with record/organization scope.

### P2-B02 — Harden and verify atomic project creation

**Severity:** Critical  
**Owner:** Backend owner
**Classification:** Genuine blocker for enabling live project creation; creation UI and validation may use a fake adapter

The existing `create_project_with_details(p_payload jsonb)` is only adoptable after verifying or fixing:

- Authorized creator role and organization scope.
- Active and organization-scoped owner/member identities.
- Duplicate-member behavior.
- Required fields, dates, milestones, ordering, and status validation.
- Atomic creation of project, owner membership, initial members, and milestones.
- Audit and intended notification side effects in the same transaction.
- Idempotency or safe duplicate-press behavior.
- Rollback on every validation or side-effect failure.

Return a stable typed result containing the created project ID and any created milestone/member identifiers required by mobile.

### P2-B03 — Add atomic project update/member/milestone contracts

**Severity:** Critical  
**Owner:** Backend owner
**Classification:** Missing live mutation capability; editing UI and state handling may continue with mocks

Current web behavior uses multiple direct writes for project fields, membership, and milestones. Mobile must not reproduce a partially committed multi-request update.

Provide authorized transactional RPCs for:

- Editing core project fields.
- Adding/removing/updating members.
- Adding/updating/reordering/completing milestones.
- Version or stale-state conflict detection.
- Audit and notification side effects.
- Archive/restore rules if restore is approved.

Project membership alone must not imply project-management authority.

### P2-B04 — Harden task creation, assignment, and deadline contracts

**Severity:** Critical  
**Owner:** Backend owner
**Classification:** Per-operation live-integration blocker; do not stop unrelated project/report development

Verify or fix `create_task_with_details`, `assign_task_with_details`, due-date RPCs, and related lifecycle operations so they enforce:

- Active and organization-scoped assignees/team members/reviewers.
- Project and milestone scope through canonical `linked_project_id` and `milestone_id`.
- Self-review prevention and reviewer eligibility.
- Valid dependency relationships and cycle prevention.
- Parent/milestone/project date boundaries.
- Locked/submitted/completed-state restrictions.
- Atomic task, participant, audit, and notification writes.
- Duplicate/stale requests and rollback behavior.

### P2-B05 — Provide minimal permission-scoped project and report reads

**Severity:** High  
**Owner:** Backend owner
**Classification:** Live data-contract dependency; report layout, filter, empty/error, and accessibility work may continue with representative fake rows

The current web reports aggregate broad client-side datasets. Mobile requires paged, minimal views or RPCs that return only authorized fields.

Freeze definitions for:

- Project health.
- Total, active, completed, overdue, due-soon, blocked, unassigned, and awaiting-review work.
- Department workload and delivery summaries.
- Report freshness/as-of time and schema version.
- Stable pagination, filtering, and sorting.

Do not expose evidence paths, private reviewer notes, personnel details, prompt context, or financial records merely to calculate a summary on the client.

### P2-B06 — Verify the new project completion/archive lifecycle

**Severity:** High  
**Owner:** Backend owner
**Classification:** Live completion/archive integration gate only; it does not block other project screens

Commit `042e1a5b` adds:

- `get_project_completion_readiness(uuid)`
- `complete_project(uuid,text)`
- `archive_completed_project(uuid,text)`
- A trigger that blocks invalid completion/archive transitions

Required before mobile adoption:

1. Confirm whether `20260831000003_project_completion_lifecycle.sql` is actually deployed. The attached evidence only establishes the Phase 1 migration claim.
2. Test authorized managers, ordinary members, unrelated users, inactive profiles, and Super Admin behavior.
3. Test no-task, incomplete-task, incomplete-subtask, governance-closeout, duplicate, stale, completed, and archived states.
4. Verify audit behavior and rollback.
5. Resolve the financial-data mismatch: the RPC currently returns cash blocker status and amount to any actor passing `can_manage_project`. Because finance is deferred from mobile Phases 1–3, either prove this is the approved permission boundary or return a redacted generic blocker for mobile/non-finance viewers.
6. Provide a stable result schema and error mapping.

The lifecycle migration helps completion/archive only. It does not satisfy project creation, editing, membership, milestones, assignment, reports, or AI.

### P2-B07 — Verify project/report Realtime behavior

**Severity:** High  
**Owner:** Backend owner
**Classification:** Release-verification gate for active-app refresh; base read/UI development may continue

Confirm publication and RLS behavior for the minimal project, milestone, membership, task, review, activity, and report invalidation sources selected for mobile. Realtime events should prompt scoped refetches; they must not carry private report rows or broaden access.

### P2-B08 — Add a narrow queued AI recommendation contract

**Severity:** Critical for the Phase 2 AI portion  
**Owner:** Gateway/AI/backend owner
**Classification:** Missing live AI capability; deterministic fake job-state UI may be developed but not claimed as live AI

No new server/gateway route was added in the inspected web update. Provide a versioned business endpoint that:

- Requires a Supabase bearer token.
- Authorizes Department Head permission and organization/report scope server-side.
- Loads private context server-side rather than accepting it from mobile.
- Uses a fixed model allowlist and server-owned prompt construction.
- Enforces input/output limits, rate/concurrency limits, timeouts, cancellation, and expiry.
- Returns typed `queued`, `running`, `succeeded`, `failed`, `expired`, and `unavailable` states.
- Scopes job reads/cancellation to the requester or an explicitly authorized role.
- Supports safe job-ID persistence and resume after app restart.
- Logs auditable metadata without raw sensitive prompts.
- Returns advisory drafts only; it cannot assign people, create tasks, approve work, or mutate a project.

Ordinary Supabase-backed project/task/report work must remain usable when the gateway or AI host is offline.

### Phase 2 backend-ready definition

Phase 2 is backend-ready when:

- Phase 1 backend prerequisites used by Phase 2 are accepted.
- P2-B01 through P2-B07 pass for the non-AI project/report slice.
- P2-B08 passes before AI recommendations are enabled.
- All adopted RPC/view/gateway contracts are versioned and represented in generated types.
- Financial fields remain excluded or safely redacted according to the finance deferral beyond the capstone sequence.

## Phase 3 — Notifications, push, chat, AI briefs, and proposal import blockers

The latest web commit contains no new server routes or migrations for the required Phase 3 push, chat, AI-brief, or proposal-extraction infrastructure. The existing mobile read-only Inbox does not satisfy Phase 3 completion.

**Development status:** Continue notification UI/read-state architecture, push permission UX, chat screens, queued-job presentation, proposal draft editing, validators, persistence boundaries, and tests behind development-only adapters. Do not register real tokens, send messages, submit private documents, start AI jobs, or commit proposals until each corresponding backend contract exists and passes authorization tests.

### P3-B01 — Complete the canonical notification contract

**Severity:** Critical  
**Owner:** Backend owner
**Classification:** Live read-state/destination integration blocker; Inbox UI work may continue

Provide a recipient-owned, paged notification surface with:

- Stable event ID, type, created time, read time, actor summary, and allowlisted destination kind/UUID.
- Recipient-only reads and mark-one/mark-all mutations.
- Stable ordering and cursor pagination.
- Deduplication/idempotency rules.
- Deleted, malformed, unsupported, and no-longer-authorized destinations.
- Realtime publication and recipient-only event delivery.
- No private feedback, report rows, chat bodies, proposal text, financial details, access tokens, or signed URLs in the notification payload.

### P3-B02 — Add device-token registration and trusted push delivery

**Severity:** Critical for push  
**Owner:** Backend/push-infrastructure owner
**Classification:** Missing live push capability; permission/settings UI and mocked event handling may continue

Provide:

- A per-user, per-installation push-token table or trusted equivalent.
- Authenticated register/update/revoke operations deriving the user from the token, not a client-provided user ID.
- Token rotation, duplicate token, account switch, sign-out, inactive profile, and invalid-token cleanup behavior.
- User notification preferences and supported event categories.
- A trusted server/Edge Function that alone owns push credentials and decides recipients/content from allowlisted business events.
- Deduplication keys, retries, push receipts, invalid-token disabling, rate limits, and redacted audit.
- A versioned minimal push payload containing only a notification ID and allowlisted destination identifiers.

An authenticated mobile user must never be able to send arbitrary push content or target another user. Foreground Realtime is not background push delivery.

### P3-B03 — Add canonical chat DDL, RLS, and server mutations

**Severity:** Critical for chat  
**Owner:** Backend owner
**Classification:** Missing live chat capability; chat UI and deterministic fake history may continue

The existing web chat behavior is not an approved mobile contract. Provide committed migrations and tests for:

- Channels and participant membership.
- Messages with server-derived sender identity.
- Paged history and stable cursors.
- Send mutation with length/content validation and idempotency.
- Read state/unread counts.
- Participant-only reads and Realtime events.
- Organization/task channel creation and membership maintenance.
- Membership removal and permission-revocation behavior.
- Edit/delete/reply/reaction/mention/attachment behavior only if implemented as first-class contracts.

If optional message features are not ready, freeze the first slice to paged text history, text send, and read state. Do not encode mutable metadata inside the text body. Offline sends must be rejected rather than automatically replayed.

### P3-B04 — Add typed queued AI management briefs

**Severity:** Critical for AI briefs  
**Owner:** Gateway/AI/backend owner
**Classification:** Missing live AI capability; queued/running/succeeded/failed UI may be developed with fake jobs

Provide a narrow versioned brief operation that:

- Starts only from an authorized Phase 2 report identifier and filters.
- Loads report rows and sensitive context server-side.
- Never accepts a client-selected model, arbitrary prompt, hidden scoring context, or broad personnel data.
- Uses requester-scoped queued jobs with bounded polling, cancellation, expiry, and restart recovery.
- Separates verified observations from advisory recommendations.
- Records report definition/version and freshness.
- Applies rate/concurrency/size limits and redacted audit.
- Cannot directly approve, assign, notify, spend, or mutate operational records.

No matching gateway/server update was present in commit `042e1a5b`.

### P3-B05 — Add private server-side proposal import

**Severity:** Critical for proposal import  
**Owner:** Backend/gateway/AI owner
**Classification:** Missing live document/AI/commit capability; draft-editing UX and validators may continue with synthetic non-sensitive fixtures

Provide:

- A private proposal-document bucket and task-scoped/owner-scoped Storage policies.
- File type, size, filename, ownership, cleanup, signed-access, and retention rules.
- Trusted server-side PDF extraction/OCR; mobile must not port browser `pdfjs-dist` behavior.
- A typed decomposition job with bounded states, validation, cancellation, expiry, and redacted errors.
- Persisted versioned drafts that users can edit.
- Participant and approval rules bound to an exact draft revision.
- One explicit, authorized, idempotent, atomic commit operation that creates the approved project/task hierarchy and returns stable IDs.
- Full rollback on validation, authorization, audit, notification, or hierarchy-creation failure.

AI output remains a draft. It cannot commit itself. Operational budget, funding, petty-cash, receipt, or allocation fields must be rejected or retained as unresolved non-operational draft text until a future separately approved financial contract explicitly supports them.

### P3-B06 — Define private report export if selected

**Severity:** Medium; only required if export is selected for Phase 3  
**Owner:** Backend owner
**Classification:** Optional feature dependency; does not block other Phase 3 work

Provide a server-generated private artifact with authorization, expiry, audit, cleanup, and signed access. Do not require mobile to download broad sensitive datasets and generate a report using browser print-window behavior.

### P3-B07 — Integrated Phase 3 security and lifecycle probes

**Severity:** Critical acceptance gate  
**Owner:** Backend plus mobile integration testing
**Classification:** Release-verification gate for implemented Phase 3 capabilities

The backend portion must support tests for:

- Notification read/update ownership, duplicates, deleted destinations, and Realtime reconnect.
- Push registration rotation, sign-out cleanup, receipt handling, invalid tokens, and inability to send arbitrary pushes.
- Chat participant scope, send identity, pagination, revocation, duplicate events, and offline rejection.
- AI job ownership, timeout, cancellation, expiry, gateway outage, and sensitive-context omission.
- Proposal upload ownership, extraction failure, malformed decomposition, stale revision, approval binding, duplicate commit, and rollback.
- Account switching, stale sessions, permission revocation, app suspension, process restart, and protected-cache cleanup.

Android/iOS foreground, background, and terminated push delivery remain mobile/device acceptance tasks, but the teammate must supply the working trusted sender and non-production event triggers needed to perform them.

### Phase 3 backend-ready definition

Phase 3 is backend-ready only for the explicitly selected features whose corresponding P3 blockers are closed. At minimum:

- Notification read/write and destination contracts are accepted.
- Push has server-owned registration and delivery if push is selected.
- Chat has auditable DDL/RLS/mutations if chat is selected.
- AI briefs have a typed authenticated queued endpoint if briefs are selected.
- Proposal import has private uploads, server extraction, versioned approval, and atomic commit if import is selected.
- Outages do not block ordinary Supabase-backed work.
- Deferred finance scope has not returned through project closeout, notifications, reports, AI, or proposal payloads.

## How to report a genuine live-integration blocker

Do not return a broad statement such as “Phase 2 is blocked by permissions.” Report the smallest failing operation so backend work stays narrow and unrelated mobile work continues.

Use this format:

```text
Phase/blocker ID:
Operation: exact table read, Storage operation, RPC, or HTTP route
Environment/project ref:
Actor: role plus actual assignment/reviewer/member/organization relationship
Record state: relevant task/project/submission/job state
Request: sanitized argument names and representative values; no secrets
Expected result:
Actual result: status/error code and redacted message
Reproduced with: test name or exact safe test command
Minimum backend change needed:
Mobile work continuing in parallel:
```

Examples of appropriately narrow blockers:

- “Assigned contributor receives Storage `403` inserting the documented subtask progress path; the new `INSERT` policy does not recognize `assigned_to`. Minimum change: correct that predicate and add assigned/unrelated JWT tests.”
- “Ordinary project member can execute the project-update RPC despite lacking management authority. Minimum change: enforce `can_manage_project` plus active profile and add a denial test.”
- “The task submission RPC commits, but the updated web client then fails cleanup because it deletes without `claim_task_evidence_cleanup`. Minimum change: update the cleanup helper; adding permissions is not a fix.”
- “No typed management-brief route exists. Minimum change: add the authenticated queued-job contract. Mobile can still implement its job-state UI with a fake adapter.”

## Required teammate handoff package

For every blocker marked fixed, return the following without secrets:

1. Feature/blocker ID from this report.
2. Source migration or server file and Git commit SHA.
3. Exact non-production project/environment where it was deployed.
4. Deployment time and sanitized result.
5. Tables/views/functions/RPCs/routes changed.
6. Authorization rule for every read and mutation.
7. Versioned request, response, error, pagination, and idempotency contracts.
8. Allowed/denied identities tested and their relationships, without credentials.
9. Integration-test command and result.
10. Realtime publication/event result where applicable.
11. Storage configuration and cleanup result where applicable.
12. Generated database types or schema-generation instructions.
13. Known limitations and intentionally deferred behavior.

Recommended completion record:

```text
Blocker ID:
Source commit:
Migration/route:
Environment/project ref:
Deployment time:
Authorization contract:
Allowed cases passed:
Denied cases passed:
Realtime/Storage/AI checks:
Generated types updated:
Known limitations:
```

## Recommended backend delivery order

1. Reconcile deployment history and confirm the shared non-production project.
2. Verify the already-applied Phase 1 evidence migration; do not reapply it solely for this report.
3. Finish bucket configuration, cleanup callers, orphan worker, and real-user evidence tests.
4. Verify Phase 1 task/review/notification/comment/Realtime contracts.
5. Freeze the Department Head permission matrix.
6. Harden project creation, update, membership, milestone, task assignment, report, and lifecycle contracts.
7. Add the typed Phase 2 queued recommendation endpoint.
8. Complete notification read-state and destination contracts.
9. Add trusted push registration and delivery.
10. Add canonical chat DDL/RLS/mutations.
11. Add typed AI brief jobs.
12. Add private proposal extraction, versioned drafts/approval, and atomic commit.
13. Run cross-client, security, lifecycle, outage, and device-support acceptance.

This order allows mobile to finish the core employee/reviewer flow before taking on Department Head and advanced-workflow complexity.

## Prohibited shortcuts

Do not:

- Put a Supabase service-role key, database password, push credential, Cloudflare credential, private AI credential, or Ollama access credential in mobile/web source or documentation.
- Make evidence, proposal, report, receipt, or other private buckets public.
- Treat `auth.uid() is not null`, a client role, or a navigation permission as sufficient authorization.
- Use service-role results as proof of employee RLS behavior.
- Blindly reset, push, or repair an unreconciled shared database.
- Expose arbitrary push-recipient or push-content endpoints.
- Expose a generic unlimited AI prompt/model endpoint.
- Send private report rows, manager notes, raw document text, chat bodies, tokens, or signed URLs in notifications, logs, analytics, or query keys.
- Automatically apply AI recommendations or proposal decompositions.
- Automatically replay approvals, assignments, chat sends, proposal commits, or financial mutations while offline.
- Count the new cash-release work toward Phase 1–3 mobile completion.

## Final completion boundary

Closing every backend blocker in this report makes the corresponding mobile workflows safe to implement and accept. It does not automatically complete their screens or native behavior.

After the backend handoffs arrive, the mobile repository must still add the remaining mutations and screens, regenerate types, add/update unit tests, run `npm run check`, run `npm run build:verify` after native/configuration changes, and complete Android/iOS device acceptance. A phase may be reported complete only when both its backend gates and mobile exit criteria pass.
