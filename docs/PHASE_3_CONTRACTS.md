# Phase 3 contract record

## Status

- Status: P3.0 is recorded and P3.2 has a partial read-only notification-inbox slice. Phase 3 is not complete.
- Mobile repository baseline: `381b27942b7dfe45fedc098c6acc76594d4661d8`
- Recorded web audit baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Upstream `main` rechecked: `7b072123a20876940be84217dbb6af3ad8d2700f` on August 30, 2026; it has not been adopted as the mobile baseline.
- Migration source inspected: `Migrations-20260827T143023Z-1-001/Migrations/`
- Deployed migration history, recipient-only notification RLS results, and non-production identity probes: not yet supplied or verified.

This record distinguishes source evidence from deployed authorization. The generated database types and supplied migration archive are useful references, but the selected non-production Supabase project remains authoritative. No Phase 3 client mutation is authorized by this document.

## Implemented mobile boundary

The app now provides a paged, read-only Inbox tab for an authenticated profile:

- Every list and direct canonical-row read includes `user_id = currentProfile.id`; RLS remains the final authorization boundary.
- The minimal read projection excludes financial-record fields and other unneeded metadata.
- Only known non-financial notification types (`approval_needed`, `completed`, and `status_change`) display their content. Unknown types—including future finance notifications—become a generic unavailable card with no actor, reason, linked ID, or destination.
- Task and project destinations are allowlisted, UUID-validated, permission-gated for presentation, and then re-read by the existing RLS-backed detail screens.
- Missing, malformed, unsupported, inaccessible, or RLS-hidden destinations do not produce an existence-revealing mobile route.

The slice does not mark a row read, mark all read, subscribe to notification Realtime, register a device, request native push permission, send a push, or persist notification content. It is not evidence that recipient-only notification policies are deployed.

## Notification source contract

| Concern | Current source evidence | Mobile rule |
| --- | --- | --- |
| Canonical row | Generated `notifications` row includes ID, recipient, type, title/message, read state, creation time, task/project references, actor, and reason. | Select only the fields required for the Inbox. Never select or render `financial_record_id` or `financial_record_type` in Phase 3. |
| Recipient scope | The supplied workflow migrations create notification rows for task events. No reviewed base policy for the table appears in the supplied archive. | Filter every client request by the signed-in profile ID and require allowed/denied deployed RLS probes before calling this a verified workflow. |
| Read state | The generated type exposes `read`, but no recipient-only update contract has been verified. | Display the returned state only. Do not issue client updates or bulk updates. |
| Destination | Generated rows have task and project UUID references. Existing mobile detail routes validate UUIDs and query the record again. | Map only task/project destinations at present; no route is created for a notification ID, financial item, chat, report, or proposal draft. |
| Foreground updates | The plan expects Realtime invalidation, but publication and recipient filtering are unverified. | Do not subscribe until allowed/denied delivery and cleanup probes pass. |

## Required non-production validation

Before enabling notification updates, Realtime, or any push work, the backend owner must provide a non-production environment and show:

1. An active recipient can list and read only their own notification rows.
2. An unrelated authenticated identity receives no rows and cannot read a guessed notification ID.
3. An inactive or missing-profile identity is denied.
4. A recipient can update only their own read state, if that product behavior is retained; bulk update behavior and audit requirements must be explicit.
5. Realtime delivers only authorized rows, stops after sign-out or access revocation, and reconnects without duplicate state.
6. Task and project destination reads return the same unavailable state for deleted, hidden, or unauthorized records.

## Blocked Phase 3 contracts

| Capability | Blocking evidence | Required backend outcome before mobile enablement |
| --- | --- | --- |
| Push registration and delivery | No device-token table, trusted sender, delivery outbox, receipt cleanup, approved provider ownership, or EAS project ID exists. | Owner-scoped token registration/revocation, server-only sender, allowlisted event mapping, preferences, minimal versioned payload, receipt processing, and Android/iOS provider credentials held outside the app bundle. |
| Chat | Generated chat types exist, but base DDL/RLS/grants are missing from the supplied migration archive; web writes allow client-supplied actor data. | Reviewed base migrations, participant-scoped reads and server-derived send/read mutations, publication, membership revocation behavior, and allowed/denied probes. |
| AI management briefs | The current gateway exposes generic AI jobs/chat with client-controlled models and prompts. Phase 2 reports are not stable. | Narrow, versioned, owner-scoped brief endpoints with server-owned context/model policy, structured advisory results, limits, audit, cancellation, and idempotency. |
| Proposal PDF import | Collaboration draft/commit migrations exist, but private upload, extraction/OCR, decomposition-job, deployed RLS, revision, and atomic-commit behavior have not been tested. | Draft-scoped private Storage, typed server extraction/decomposition, revision-bound approvals, duplicate-safe atomic commit, and allowed/denied probes. |

## Explicit Phase 4+ deferral

Budget and petty-cash workflows remain excluded from Phase 3. Notification records with financial metadata or unknown finance-related types must not create a finance route, reveal financial content, or reintroduce financial implementation work through this Inbox. Reconsider them only after a separate Phase 4+ upstream audit confirms stable deployed schema, RLS, RPC, Storage, lifecycle, and role behavior.

## Next implementation gate

The next safe notification increment is recipient-only RLS and update/Realtime validation against a non-production project. Push begins only after the independent device-registration and trusted-sender contract is deployed. Chat, briefs, and proposal import remain blocked at their listed contract gates.
