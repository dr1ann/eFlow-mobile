# eFlow Mobile Phase 1 — Blocking Issues and Backend Handoff

- Report date: August 29, 2026
- Mobile repository: `eFlow-mobile`
- Current mobile status: P1.1 implemented; guarded read-only Work/task/subtask routes and local evidence-picker preview are testable; Phase 1 is not complete
- Recorded web baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`
- Latest web `main` inspected: `7b072123a20876940be84217dbb6af3ad8d2700f`

## Executive summary

Phase 1 is blocked at the boundary between the mobile client and the deployed Supabase backend.

The most critical blocker is task-evidence Storage authorization. The buckets are private, but the current schema defines `taskfiles_rw` as an `ALL` policy allowing any authenticated user to access objects in `task-attachments` and `task-files`. That is not task-scoped authorization and cannot safely be used by mobile. See the [current upstream policy](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/blob/7b072123a20876940be84217dbb6af3ad8d2700f/supabase/fresh_schema.sql#L1206-L1220).

There are also unverified live RLS/RPC behaviors, missing test identities, empty Supabase CLI migration history, unverified Realtime publications, and incomplete Android/iOS acceptance.

Fixing Storage alone will unblock evidence implementation, but it will not make Phase 1 complete. The safe read-only screens now exist; workflow mutations, reviews, communications, remaining read views, and end-to-end acceptance still need implementation afterward.

## What is already complete on mobile

The following foundation work is present:

- Generated Supabase database types from the linked non-production project.
- Verified 61 supplied migration files through upstream baseline `508aabc`.
- Typed task, subtask, review, notification, announcement, discussion, and project contracts.
- Runtime row mappers and malformed-row handling.
- Task/subtask selectors, filters, submission readiness, reviewer eligibility, and query keys.
- Effective Task Lead behavior:
  - `assigned_to` takes precedence.
  - `recommendation_lead_id` is only used when `assigned_to` is null.
  - A role name or AI recommendation does not grant task-leader authority.
- Native evidence normalization and client-side file-validation groundwork.
- A permission-gated Work tab with a virtualized, paged, filterable task feed.
- Guarded task/subtask UUID routes and RLS-backed read-only details.
- Local-only document/image picker preview for an assigned contributor; selected metadata is displayed without upload, persistence, or URI logging.
- Supabase error normalization.
- Expo SDK 57-compatible dependencies.
- Phase 1 contract and implementation documentation.

Current validation:

- `npm run check` passed.
- 29 Jest suites passed.
- 96 tests passed.
- Lint passed.
- TypeScript checking passed.
- `npm run build:verify` passed for Android and iOS exports.
- `npx expo-doctor` passed all 21 project checks.

The app retains the Phase 0 Home gateway diagnostic and Settings route. It now adds the partial Work/task/subtask read path above. Reviews, Inbox, workflow mutations, evidence transfer, and the remaining Phase 1 screens have not yet been delivered.

Relevant mobile documentation:

- [Phase 1 readiness gate](PHASE_1_IMPLEMENTATION_PLAN.md#phase-0-readiness-gate)
- [Phase 1 contract blockers](docs/PHASE_1_CONTRACTS.md#deliberately-unverified-and-blocked)
- [Phase 1 roadmap exit criteria](MOBILE_IMPLEMENTATION_PHASES.md#exit-criteria-1)

## Blocking issue 1: Task-evidence Storage authorization

**Severity:** Critical  
**Owner:** Web/backend/Supabase owner

The current upstream schema creates private buckets, but its policy is effectively:

```sql
create policy taskfiles_rw
on storage.objects
for all
using (
  bucket_id in ('task-attachments', 'task-files')
  and auth.uid() is not null
)
with check (
  bucket_id in ('task-attachments', 'task-files')
  and auth.uid() is not null
);
```

This means any authenticated account may potentially read, upload, overwrite, or delete another task's evidence if it knows or discovers the object path.

None of the 61 supplied migrations replaces this with a task-scoped object policy.

### Required backend work

Create a reviewed migration in the web/backend repository that:

1. Drops or replaces `taskfiles_rw`.
2. Keeps evidence buckets private.
3. Defines a canonical object-path structure containing enough identifiers to authorize access, such as:
   - Task ID.
   - Subtask ID where applicable.
   - Submission/attempt UUID.
   - Unique object identifier.
4. Adds separate operation-specific policies:
   - `INSERT`: only an eligible contributor or effective Task Lead may upload for the relevant workflow.
   - `SELECT`: only authorized task participants and eligible reviewers may read.
   - `DELETE`: only controlled cleanup of unfinalized uploads, preferably uploader-scoped or backend-owned.
   - `UPDATE`: disable unless there is a proven requirement; submitted evidence should remain immutable.
5. Prevents unrelated authenticated employees from accessing objects.
6. Defines:
   - MIME allowlist.
   - Maximum file size.
   - Maximum files per submission.
   - Signed-URL lifetime.
   - Whether filenames may be retained or must be replaced with generated names.
7. Defines orphan cleanup:
   - Client compensating deletion when an RPC fails.
   - Server-side reconciliation or age-based cleanup for interrupted uploads the client cannot delete.
8. Prevents overwriting previously submitted evidence.

Client-side validation will still be implemented, but it is not authorization.

## Blocking issue 2: Live RLS and workflow RPC behavior is unverified

**Severity:** Critical  
**Owner:** Backend and mobile integration testing

Generated types confirm table shapes and RPC signatures. They do not prove that deployed policies allow and deny the correct users.

The following RPCs require live non-production testing:

- `transition_task_status`
- `save_subtask_progress`
- `submit_subtask_for_review`
- `decide_subtask_review`
- `submit_task_for_review`
- `decide_task_review`

At minimum, verify:

| Workflow | Expected allowed identity | Required denied identities |
| --- | --- | --- |
| Read assigned work | Assigned contributor | Unrelated employee |
| Save subtask progress | Assigned contributor | Unassigned employee |
| Submit subtask | Assigned contributor with valid evidence | Unassigned, stale, duplicate, or offline attempt |
| Decide subtask review | Resolved reviewer | Submitter, unrelated user, wrong reviewer |
| Manage subtask structure | Effective Task Lead | Contributor without lead authority |
| Submit parent task | Effective Task Lead after all subtasks are approved | Contributor, unfinished-task state |
| Decide parent review | Server-resolved primary/backup reviewer | Submitter, wrong reviewer, unrelated employee |
| Read evidence | Authorized participant/reviewer | Unrelated authenticated user |
| Delete temporary evidence | Authorized cleanup actor | Other authenticated users |

Self-review denial must be proven at both subtask and parent-task levels.

## Blocking issue 3: Required non-production test identities

**Severity:** Critical for acceptance  
**Owner:** Backend owner/project administrator

Provide active non-production accounts or records representing:

- Assigned employee/contributor.
- Effective Task Lead.
- Primary reviewer.
- Backup reviewer.
- Unrelated employee.
- Self-review collision.
- Inactive profile.
- Missing or malformed profile.
- Unsupported role if such a role can authenticate.

Credentials must be transferred securely and must not be committed, placed in documentation, logged, or pasted into public agent prompts.

The accounts also need representative task records connecting them through real assignment and reviewer relationships. Role labels alone are insufficient.

## Blocking issue 4: Supabase migration history is empty

**Severity:** High deployment/audit risk  
**Owner:** Backend/Supabase owner

As of August 29, 2026:

```text
npx supabase migration list --linked
{"migrations":[],"message":"Migrations listed"}
```

The deployed schema is not empty—the generated database types contain the expected tables and functions. This indicates that the schema was likely applied outside normal Supabase CLI migration tracking or that the history was never registered.

This does not automatically prevent existing queries from running. It does prevent the team from confidently proving which migrations and policies are deployed.

### Required resolution

The backend owner should:

1. Document how the current schema was deployed.
2. Compare live functions, policies, triggers, publications, and bucket configuration with the migration source.
3. Establish an auditable baseline before applying further migrations.
4. Decide how migration history will be reconciled.
5. Apply the evidence-security migration through the agreed backend deployment process.

Do not blindly run:

- `supabase db push`
- `supabase db reset`
- `supabase migration repair`

These operations could misrepresent or damage the shared environment if performed before reconciling the actual deployment history.

The migration source belongs in the web/backend repository, not the mobile repository.

## Blocking issue 5: Realtime and communication policies are unverified

**Severity:** High  
**Owner:** Backend plus mobile integration testing

Confirm the deployed Realtime publication for all Phase 1 tables that mobile will subscribe to, including as applicable:

- `tasks`
- `subtasks`
- `subtask_progress_updates`
- `subtask_submissions`
- `subtask_submission_attachments`
- `task_submissions`
- `notifications`
- `announcements`
- `announcement_recipients`
- `task_comments`

Also prove:

- Notifications are readable and updateable only by their recipient.
- Announcement audience and expiration rules are enforced.
- Task comments are readable/insertable only by authorized task participants.
- A task-linked project can be read only by an authorized user.
- Realtime does not expose rows the same identity could not select normally.

A live web-to-mobile event probe is required; seeing a table in source migrations is insufficient.

## Blocking issue 6: Phase 0 authentication and device acceptance

**Severity:** Required gate  
**Owner:** Mobile team with test identities/devices

The following remain unverified on the shared environment:

- Active employee and reviewer sign-in.
- Cold session restoration.
- Token refresh.
- Sign-out and user-switch cleanup.
- Inactive, missing, malformed, and unsupported profiles fail closed.
- One authenticated Supabase read succeeds.
- One authenticated gateway health request succeeds.
- Unauthorized direct deep links cannot expose protected or cached data.
- Android session, picker, keyboard, safe-area, accessibility, and reconnect behavior.
- iOS session, picker URI, permissions, keyboard, safe-area, accessibility, and reconnect behavior.

Native Android and iOS exports currently build successfully, but an export build is not device acceptance.

## Blocking issue 7: Upstream has advanced beyond the recorded baseline

The recorded mobile baseline is `508aabc`, but current web `main` is [`7b072123a20876940be84217dbb6af3ad8d2700f`](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/commit/7b072123a20876940be84217dbb6af3ad8d2700f), seven commits ahead of the mobile baseline. The old repository URL now redirects to the `GabrielCahiyang` owner. See the [baseline comparison](https://github.com/GabrielCahiyang/eFlow-e-Governance-Project/compare/508aabc8881630b37a62a973645ecb0bb386e99e...7b072123a20876940be84217dbb6af3ad8d2700f).

The initial comparison found no new Supabase migration files in those seven commits. Most changes concern the web application shell, project workspace, styling, repository cleanup, and login presentation. However, these Phase 1-adjacent files changed and should be classified:

- Login page and development quick-login behavior.
- Shared role presentation.
- Task status presentation.
- `TaskDetailDrawer`.
- Review inbox components.
- Project query/workspace behavior used by Phase 1's read-only related-project view.

This appears to be a compatibility-review/sign-off item rather than a new database-security blocker, but the recorded baseline must not be updated until the relevant changes are classified and verified.

## Mobile work remaining after the backend is unblocked

Even after the backend requirements are completed, the following mobile work packages remain or remain partially complete:

- P1.2: finish Reviews, Inbox, account completion, badges, and their guarded routes; Work plus task/subtask routes are partial.
- P1.3: finish My Subtasks, Work I Am Leading, deadlines, history, project/evidence reads, and deployed acceptance; My Tasks plus basic task/subtask details are partial.
- P1.4: Start work, progress forms, evidence upload, cleanup, and subtask submission.
- P1.5: Subtask reviewer inbox, approval, and changes-requested lifecycle.
- P1.6: Parent-task submission and primary/backup review.
- P1.7: Notifications, announcements, task comments, and foreground Realtime.
- P1.8: End-to-end hardening, Android/iOS acceptance, accessibility, privacy, and sign-off.

Therefore, “security configured” means the next mobile implementation work can safely proceed; it does not mean Phase 1 is automatically finished.

## Required handoff from the teammate's agent

Return the following without including secrets:

1. The committed migration filename and commit SHA.
2. Confirmation that it was applied to the shared non-production Supabase project.
3. Exact bucket IDs and confirmation that they remain private.
4. Canonical task and subtask evidence path formats.
5. Policy names and authorized identities for `SELECT`, `INSERT`, `DELETE`, and, if enabled, `UPDATE`.
6. MIME, size, count, and signed-URL limits.
7. Orphan-cleanup owner and mechanism.
8. Allowed/denied RLS and RPC integration-test results.
9. Realtime publication status and live-event results.
10. Test-identity roles and relationships, with credentials shared separately and securely.
11. Migration-history reconciliation status.
12. Classification of upstream changes from `508aabc` through `7b07212`.
13. Any schema changes requiring mobile database-type regeneration.

## Prohibited shortcuts

Do not:

- Put a Supabase service-role key in the mobile app.
- Make task-evidence buckets public.
- Retain `auth.uid() is not null` as the only task-file authorization.
- Trust client-side role checks as security.
- Use public evidence URLs.
- Allow evidence overwrite after submission.
- Treat the database JSON dump as proof of RLS, RPC, Storage, or Realtime behavior.
- Repair or push migration history blindly.
- Send test passwords, access tokens, or private file URLs through source control or logs.

## Bottom line

The immediate hard stop is missing task-scoped evidence Storage security plus live allowed/denied authorization testing. Migration auditability, test identities, Realtime verification, device acceptance, upstream classification, and the remaining mobile work packages are also required before Phase 1 can be declared complete.
