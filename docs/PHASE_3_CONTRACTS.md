# Phase 3 contract record

## Status — September 3, 2026

- Full-integration plan: [PHASE_3_IMPLEMENTATION_PLAN.md](../PHASE_3_IMPLEMENTATION_PLAN.md).
- Mobile commit inspected: `3921e63e23b6b417099cf2da0636f7dd1a8e53c5`.
- Recorded web compatibility baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`.
- Remote web `main` checked: `042e1a5b240cf667eb3dfa69d263897686de2a04`.
- Phase 3 status: partial shared Inbox implementation; full integration planned.
- Deployed Phase 3 RLS/RPC/Storage/gateway/sender probes: not performed or established by this planning change.

This revision supersedes the August 30 Phase 3 source assessment. Readiness is recorded separately for mobile code, live contract integration, and release acceptance. Missing backend operations do not block independent screens, adapters, validators, synthetic fixtures, or tests. Fixtures must be development-only, visibly identified, and isolated from live writes.

The upstream SHA is an inspection reference, not an adopted mobile baseline. Source policies/types do not prove deployment or authorization. The mobile repository does not apply or rerun teammate-owned migrations.

## Implemented mobile boundary

- Recipient-filtered 25-row notification feed and canonical single-row lookup.
- Minimal notification projection; unknown event types are redacted to an unavailable item.
- Validated, permission-gated task/project routes with a fresh destination read.
- Phase 1 adapters for mark-one and mark-all read; the Inbox exposes mark-one when `notificationWrites` is enabled.
- Recipient-scoped notification Realtime invalidation when `phase1Realtime` is enabled.
- The Inbox still renders a stale unconditional read-only warning and lacks surfaced mark-read errors, unread-count/filter/mark-all UI, and canonical recipient re-fetch on every notification open.

No native push, standing organization/task chat, management briefs, resumable AI jobs, or PDF import is implemented. Mark-one/Realtime code must not be described as absent, and default-disabled flags must not be confused with proof the live operation passed.

## Source assessment

References below are pinned to the inspected web commit:

| Contract area | Source | Assessment |
| --- | --- | --- |
| Notifications | [fresh schema](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/fresh_schema.sql), [email router](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/server/routers/notifications.py) | Own-row SELECT/UPDATE source policies exist, but exact deployed grants, read-only column updates, inactive denial, and trusted event creation are unverified. The source INSERT policy permits authenticated callers; the email router accepts recipient/content inputs. Neither is an approved push sender. |
| Push | Committed schema/migrations and server-router inventory at the same commit | No device-token registration contract, trusted push sender, delivery outbox, or receipt cleanup found in the inspected source. This does not prove no separately deployed service exists; request its contract if the team has one. |
| Chat | [fresh schema](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/fresh_schema.sql), [chat service](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/src/app/services/chatService.ts) | Base DDL exists. Broad authenticated channel/member write policies need reconciliation with authoritative membership. Message sender ID is checked in source, but display name/read timestamps and other web payload behavior are client-controlled. |
| Briefs/jobs | [AI router](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/server/routers/ai.py), [brief service](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/src/app/features/reports/services/managementBriefService.ts) | Generic authenticated jobs/chat proxy exists; clients supply model/messages. A report-scoped brief create/status/cancel contract is not evidenced. Mobile Phase 2 report integration is also absent. |
| Proposal source | [collaboration drafts](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/migrations/20260821000001_collaboration_drafts.sql), [security](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/migrations/20260821000002_collaboration_security.sql) | Private `proposal-drafts` source policies and draft/revision APIs exist. Source association, upload attempt immutability, cleanup, concurrent save handling, and deployed authorization require verification/hardening. |
| PDF extraction | [browser extractor](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/src/app/features/proposal-import/services/pdfTextExtractor.ts) | Uses browser `File`/`pdfjs-dist`; no typed server PDF extraction/decomposition route was found in the inspected routers. |
| Publication | [atomic commit](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/migrations/20260821000004_collaboration_commit.sql), [department publication](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/migrations/20260824000006_publish_latest_department_proposal_revision.sql) | Collaboration commit takes draft/revision IDs; department publication takes a draft ID and may finalize the latest working snapshot. Expected-version safety and the correct approval route must be preserved. |
| Publication side effects | [latest source funding trigger definition](https://github.com/Rivaly-Kun/eFlow-e-Governance-Project/blob/042e1a5b240cf667eb3dfa69d263897686de2a04/supabase/migrations/20260824000007_task_budget_daily_petty_cash_workflow.sql) | Requires a task funding schedule and locked owner budget, writes a commitment, and may create allocations/ledger entries. Even a no-cost schedule does not establish a non-financial commit. This conflicts with the mobile Phase 4 finance deferral. |

The baseline-to-main diff adds task evidence, cash-release override, and project-completion migrations, with proposal/collaboration UI changes; it does not supply the missing Phase 3 push or typed document/brief services.

## Operation ledger and minimum changes

These are integration gates, not blanket development stops. “Source gap” means no live failing request was executed; do not invent an HTTP response or claim a successful probe.

| ID | Exact operation or surface | Current evidence | Minimum contract/probe needed | Mobile work that can continue |
| --- | --- | --- | --- | --- |
| P3-C01 | `notifications` SELECT, read-field UPDATE, unread total, scoped Realtime | Recipient-scoped feed/filter/count, mark-one/mark-all adapter, canonical open, and subscription code now exist; live probes unrecorded | Prove recipient/active-profile scope, read-column restriction, trusted insertion, event classification, stable paging and bounded mark-all cutoff/count. Remove any conflicting permissive grants/policies. | Local UI/tests are complete for the present request shape. Enable only after the per-operation probes; backend cutoff/count is still required for exact mark-all semantics. |
| P3-C02 | Register/rotate/revoke an installation token; trusted event delivery | Source gap; app lacks declared notification module/EAS ID | Owner-derived registration and preferences, environment isolation, sender/outbox, retry/receipts, invalid-token handling, offline sign-out expiry/revocation contract and team credential ownership | Native adapter boundary, opt-in UI, token state/response tests, development build preparation |
| P3-C03 | `chat_channels`, `chat_channel_members`, `chat_messages`; send/read-state operations | Base source exists with broad member/channel policies; no accepted mobile mutation contract. A synthetic, local-only channel/message/composer preview exists behind a development fixture flag. | Prevent self-enrollment, enforce real membership/active profile, derive identity and read cursor server-side, add bounded paging and duplicate-safe sends | Continue the local preview and its tests. Do not enable it as live chat or use it to demonstrate membership. |
| P3-C04 | Chat edit, reaction and private attachment operations | No accepted first-class mobile contract | Author/version edit rule, unique reaction actor, private association/finalization/cleanup rules; reconcile legacy encoded content | UI, codec/validator/file tests; text integration independently |
| P3-C05 | Typed report-based brief create/status/cancel | Source gap; only generic jobs/chat endpoints found. Shared state/backoff/identifier persistence is implemented with no endpoint wired. | Versioned report DTO and scoped report lookup; owned typed jobs, limits, cancellation/expiry, idempotency/recovery, structured source-linked/advisory results | Connect typed synthetic then live adapters to the shared job foundation; presentation remains to implement. |
| P3-C06 | Proposal draft creation, source upload/finalize/read/cleanup, extraction/decomposition job | Private bucket/draft APIs exist; processing/finalization contract incomplete | Draft-first source association, immutable upload attempts, server file checks/OCR decision, cleanup, typed owned jobs | PDF picker/validation and job/recovery screens |
| P3-C07 | Draft autosave/revision save and approval/readiness | Source APIs exist; expected-version argument not evidenced | Atomic conflict detection, safe field-scoped editing/projection, exact role/revision/participant rules; verify owner-only and external collaboration routes separately | Native draft editor, validation/conflict/review screens |
| P3-C08 | `commit_collaboration_draft(uuid, uuid)` / `publish_department_proposal(uuid)` | Source enforces funding and can create financial records; no live call made | Backend/product-approved non-financial commit path with expected revision, no financial side effects, atomic rollback, duplicate-result reconciliation and stable created IDs | Saved draft/review workflow; clear web handoff with commit still marked partial |
| P3-C09 | Android/iOS real workflow, role denial, restart/revocation | Release verification unrecorded for Phase 3 | Appropriate test identities/devices/builds and sanitized positive/negative evidence per enabled operation | Other implemented workflows and their targeted tests |

For P3-C08, source may reject absent funding with `22023`; this is source-derived behavior, not a reproduced SQL result. Do not set all tasks to “no cost,” disable a trigger, strip required finance fields from the shared snapshot, or alter RLS to make publication pass. Budget UI remains deferred.

## Proposed interfaces — not deployed contracts

Freeze actual operation names/signatures with the backend before connecting live adapters:

- Push payload v1: `{ version: 1, notificationId: UUID }`; resolve the canonical recipient row and re-authorize its target. No arbitrary URL or confidential body.
- Registration: installation/app/environment identity and token; authenticated backend derives user. Define ownership transfer, lease/expiry and revoke response.
- Chat send: channel reference, plain body, stable client request key; server returns canonical identity/time/message ID. Edits/reactions/files use separate typed fields/contracts.
- Brief create: approved report reference plus bounded filters; no client prompt/model/context. Status/cancel take a server-owned opaque job reference.
- Proposal source: draft reference, validated source metadata and authorized upload association; jobs use source references.
- Draft save/commit: server-enforced expected version/revision and authoritative readiness. Never allow an unseen latest autosave to be committed just because the confirmation was opened earlier.

Shared job persistence contains only user/environment/operation/reference IDs and bounded timestamps/expiry; re-fetch protected results after restart. Production must reject fixture mode, and live failure must never fall back to synthetic success.

## Evidence required for each enabled operation

Record:

- Source SHA and deployed version/project/environment.
- Exact table/RPC/route and sanitized request shape.
- Actor role plus actual assignment, channel membership, organization, reviewer or draft relationship.
- Relevant record state and expected outcome.
- Actual response/error, or explicitly “not probed.”
- Allowed and denied cases, inactive/revoked/cross-account cases where relevant.
- Unit/integration command results and Android/iOS coverage where native behavior matters.
- Smallest remaining backend change and the independent mobile work continuing.

Do not include credentials, JWTs, tokens, private notes, chat/PDF/report contents, or private URLs in the ledger.

## Decisions and ownership still needed

- Existing team push/EAS project, APNs/FCM credential owner, application identity, allowed events/preferences, and registration retention/expiry.
- Actual chat participant rules, edit window, reaction schema, attachment limits/retention, and legacy compatibility.
- Phase 2 report definition/DTO and brief job limits/result visibility.
- Proposal file/page limits, OCR behavior, source cleanup, scoped snapshot editing, conflict/version contract, and the non-financial commit decision.
- Exact Assistant Head and Super Admin authority per operation, without holding unrelated operation implementation.
- Templates, performance, export, calls, direct messages and broad governance remain unselected/deferred.

The local implementation added focused Inbox, chat-fixture, job-contract, and job-persistence tests. It ran no live probe, migration, push send, or financial operation. See the full plan for the required live and device acceptance evidence.
