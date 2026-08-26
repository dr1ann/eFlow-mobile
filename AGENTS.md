# eFlow Mobile — Repository Instructions

This file gives every Codex task working in this folder the durable project context that is not carried between conversations. Keep it accurate and concise. Do not store secrets here.

## Start here

Before planning or changing the app:

1. Read `MOBILE_IMPLEMENTATION_PHASES.md` in full.
2. Inspect the current workspace and version-control status; preserve existing user changes.
3. Identify the current implementation phase and finish the smallest complete vertical workflow that advances it.
4. If the work depends on the web application, compare the upstream commit with the recorded baseline before copying a contract or behavior.

The mobile project is now initialized as a Git repository with an Expo scaffold, Jest test setup, quality workflow, and initial Phase 0 source code. Recheck the current state before working because this description will continue to evolve.

## Project mission

Build a cross-platform mobile client for eFlow with Expo, React Native, and TypeScript. The upstream web application is the product and backend reference, but it is unfinished and its current UI is not the final design.

The intended 70/30 scope means approximately 70% of the completed, production-backed, high-frequency user journeys—not 70% of the web screens, files, or lines of code. A hard-coded demonstration screen does not count as a completed feature.

Prioritize real employee, Team Leader, and Department Head workflows. Keep complex administration and desktop-first work on the web unless the user explicitly changes the scope.

## Canonical references

- Mobile roadmap: `MOBILE_IMPLEMENTATION_PHASES.md`
- Upstream web repository: <https://github.com/Rivaly-Kun/eFlow-e-Governance-Project>
- Audited web baseline: `0ecffafffc1fc06b5c12b66014301e78aa659cde`
- Baseline recorded: August 25, 2026

The baseline is an audit marker, not a dependency pin. Update it only after comparing the old and new upstream commits, evaluating mobile impact, implementing any required compatibility work, and verifying the mobile app.

## Current architecture understanding

The audited web system uses:

- React 19, TypeScript, and Vite for the browser client.
- Supabase Auth, PostgREST, database RPCs, Storage, Realtime, migrations, and row-level security.
- A Python FastAPI control gateway, normally on `127.0.0.1:8322`.
- A separate AI service, normally on `127.0.0.1:8321`, backed by Ollama and `deepseek-r1:8b` on the team's AI host.
- A Cloudflare tunnel that publishes the gateway endpoint through Supabase `system_config`.

The intended mobile data paths are:

```text
Expo app -> Supabase Auth / database RPCs / Storage / Realtime
Expo app -> published gateway URL + Supabase bearer token
Gateway  -> private AI service -> Ollama model host
```

The phone must not run the AI model and does not need a GPU. AI features depend on the team's server being reachable; ordinary Supabase-backed work must remain usable when AI is unavailable.

Treat the deployed Supabase schema, RLS policies, RPCs, storage rules, and authenticated server routes as authoritative. Client-side guards improve UX but are never the security boundary.

## Delivery order

Follow the phase definitions and exit criteria in the roadmap:

1. Phase 0: application shell, routing, authentication, role resolution, clients, query layer, tests, and design tokens.
2. Phase 1: the employee-to-reviewer vertical slice—tasks, subtasks, evidence, submission, review, notifications, and announcements.
3. Phase 2: Department Head operations, projects, reports, and safely queued AI recommendations.
4. Phase 3: budget, push, chat, AI briefs, proposal import, and other advanced workflows.

Do not pull Phase 3 complexity into the foundation unless it is genuinely required by an earlier end-to-end workflow.

## Reuse and rewrite boundaries

The web repository is a behavior and contract reference, not a React Native template.

Usually safe to adapt after verification:

- Pure TypeScript types, enums, selectors, validators, mappers, and calculation rules.
- Supabase table/view expectations, RPC names and payloads, storage paths, and Realtime channel contracts.
- Role, permission, task-state, dependency, submission, and review rules.
- FastAPI request/response types and AI queued-job states.

Rewrite for native mobile:

- HTML elements, CSS, browser layout, Radix, MUI, Carbon, and desktop dashboards.
- React Router navigation and browser globals such as `window`, `document`, and `localStorage`.
- Browser file input, drag-and-drop, print windows, Tiptap, and `pdfjs-dist` workflows.
- Desktop Kanban, organization-tree, timeline, and data-grid interactions.
- Browser WebRTC and media-device code.

Use native navigation, document/image pickers, secure storage, virtualized lists, mobile forms, safe areas, keyboard handling, and platform-appropriate accessibility. Preserve business behavior rather than pixel-copying the unfinished web design.

Do not introduce Firebase merely because a legacy web hook or filename mentions it; verify the implementation. The audited system is Supabase-backed.

## Mobile implementation defaults

Unless the user or an established project decision says otherwise:

- Use Expo with TypeScript and Expo Router.
- Organize product code by feature, with shared `contracts`, `lib`, and `theme` modules.
- Use the public Supabase anon/publishable key only.
- Persist authentication with a SecureStore-compatible adapter.
- Use generated Supabase database types where possible.
- Use TanStack Query for remote state, invalidation, retry policy, and mutation state.
- Keep server state out of large global stores.
- Resolve the gateway through a dedicated typed client; support timeouts, cancellation, typed errors, and one endpoint refresh if a rotating tunnel becomes stale.
- Persist long-running AI job IDs and resume status checks after navigation or app restart.
- Use Supabase Realtime for active-app updates, not as a substitute for background push notifications.
- Keep business contracts and UI components separate so the final redesign can replace presentation without rewriting integrations.

Prefer one complete workflow over many disconnected screens. Avoid speculative abstractions until at least two real features need them.

## Security and privacy rules

These are non-negotiable:

- Never put a Supabase service-role key, database URL, SMTP credential, Cloudflare credential, private AI key, or Ollama access credential in the mobile bundle, source control, documentation, logs, or screenshots.
- Never use client-side role checks as authorization. Every sensitive read and mutation must be enforced by RLS, an RPC, or an authenticated server route.
- Use private storage buckets or signed access for evidence, receipts, reports, and documents as appropriate.
- Validate file type and size before upload, sanitize names, and clean up an uploaded object when the related database transaction fails.
- Do not log access tokens, private manager notes, report contents, personnel data, financial details, or AI prompts containing sensitive information.
- Check authorization again when opening a deep link or notification destination.
- Treat financial mutations, approvals, role changes, and permission changes as online-only operations. Do not replay them automatically from an offline queue.
- Ensure server notification/email routes authorize the business event and recipient; an authenticated client must not be able to send arbitrary mail.
- Configure explicit production origins and backend exposure even though native apps are not protected by browser CORS.
- Keep AI output advisory and auditable. It must not directly assign people, approve work, spend funds, or commit imported proposals.

## AI integration rules

Mobile calls the eFlow gateway; it does not call Ollama or the private AI service directly.

For queued AI jobs, send the signed-in user's Supabase access token to the gateway, create the job through the authenticated route, store the returned job ID, and poll or resume with bounded backoff. Do not keep a screen awake or poll continuously for hours.

Prefer narrow, typed business endpoints over a generic arbitrary-prompt endpoint. Backend AI work should enforce:

- Role and permission authorization.
- Model allowlists.
- Input and output size limits.
- Rate limits and concurrency limits.
- Timeouts, cancellation, and useful failure states.
- Audit events without sensitive raw prompt logging.
- Server-side assembly of private context such as manager notes.

Any recommendation, brief, or proposal decomposition must be shown as a draft and require explicit human confirmation before an atomic database mutation.

The currently described Quick Tunnel is acceptable for a controlled capstone demonstration but is not a dependable production endpoint. Plan for a named tunnel or stable hosted gateway before a serious deployment.

## Known project concerns

Revalidate these concerns whenever the upstream changes:

1. **Mock versus live features:** several Executive, Legislative, Finance, and HRMO screens in the audited web version use hard-coded demonstration data. Do not port or count them until a live contract exists.
2. **Upstream churn:** the web app and visual design are still changing. Isolate integration logic from UI and adopt only approved or contract-relevant changes.
3. **Weak upstream change control:** the audited repository used an unprotected `main`, had no visible pull-request history, and included broad commits. Recommend protected branches, small feature PRs, migrations reviewed separately, and versioned contract notes.
4. **Contract drift:** database migrations, RLS, RPC signatures, storage policies, roles, or FastAPI payloads can break mobile without visible UI changes.
5. **Role-name mismatch:** persisted values such as `super_admin`, `dept_head`, and `assistant_head` may differ from UI labels or aliases such as `superadmin` and `depthead`. Maintain one tested canonical role mapper.
6. **AI availability:** the separate AI repository/service was not part of the audited web repository. Confirm its API, deployment, model, limits, and ownership before treating AI as production-ready.
7. **Generic AI exposure:** do not let a client choose arbitrary models or send unlimited prompts. Introduce typed business operations and server-side controls.
8. **Sensitive recommendation context:** private manager notes or scoring context must be assembled server-side and must not be returned to unauthorized mobile users.
9. **Background execution:** mobile operating systems suspend apps. Persist job IDs and workflow drafts; make refresh and recovery explicit.
10. **PDF processing:** upload documents and extract/validate text on a trusted server. Do not port browser `pdfjs-dist` and `File` APIs to native.
11. **Notifications:** foreground Realtime does not deliver reliable background notifications. Expo push requires per-device token registration and a trusted sender.
12. **Offline conflict risk:** cache safe reads if useful, but do not automatically queue sensitive state transitions.
13. **Native call complexity:** audio/video calls require a separate native WebRTC, permissions, lifecycle, TURN, and background-behavior evaluation.
14. **Repository hygiene:** the audited web repository included generated or local artifacts such as `server/.venv`, `.vs`, `__pycache__`, and temporary PDF images. Never copy them into mobile; add appropriate ignore rules.
15. **Testing and CI:** do not call a workflow complete without type checks, targeted tests, and validation against the same backend contracts used by web. Establish CI before release work.
16. **Scope drift:** wait for an explicit product decision before treating the 70/30 split, final roles, final navigation, or redesigned visuals as fixed.

## Upstream update procedure

When the user supplies the web repository again or asks to sync a new push:

1. Fetch or inspect the current upstream `main` SHA and compare it with the baseline above.
2. Review changes in this order:
   - Supabase migrations, RLS, RPCs, triggers, views, and storage policies.
   - FastAPI authentication, routes, and payload contracts.
   - Roles, permissions, navigation access, and lifecycle rules.
   - Task, subtask, review, project, budget, notification, and governance behavior.
   - Shared pure logic and types.
   - AI endpoints and queue behavior.
   - UI-only changes.
3. Classify each change as required compatibility work, approved feature/design work, web-only work, or unfinished/mock work.
4. Update the mobile parity notes and relevant contracts.
5. Implement only in-scope changes and run affected tests.
6. Replace the baseline SHA in this file and the roadmap only after compatibility is verified.

Do not automatically mirror every push. A security or schema change may be urgent; a rearranged desktop dashboard may have no mobile impact.

## Testing and verification policy

Testing is part of implementation, not a later cleanup phase. For every feature, bug fix, refactor, configuration change, dependency change, or upstream compatibility update:

1. Identify the behavior and contracts that can change.
2. List the applicable tests before or while implementing.
3. Add or update those tests in the same change.
4. Run the smallest useful targeted tests during development.
5. Run the required broader validation before reporting completion.
6. If no automated test is useful, explicitly state `Tests: not applicable` and give the concrete reason and the manual or static verification performed instead.

Do not create meaningless tests merely to produce a `.test` file. Documentation-only edits, comment-only edits, and purely static visual-token changes may not need unit tests. Any change to executable behavior, permissions, validation, data mapping, state, side effects, navigation, or error handling does.

### Current test foundation

- Test runner: Jest through the `jest-expo` preset.
- Component and hook tests: React Native Testing Library.
- Shared setup: `src/test/setup.ts`.
- Test filenames: colocate `*.test.ts` with pure logic and `*.test.tsx` with hooks or rendered components. Use a clearly named integration-test location only when several features share the same scenario.
- Do not connect automated unit tests to production Supabase, production storage, the live gateway, or the AI host. Use controlled fakes or mocks for unit tests and an explicitly configured non-production environment for integration tests.
- Prefer assertions on user-visible behavior, returned contracts, state transitions, and side effects. Snapshot-only tests are not sufficient for important behavior.
- Do not weaken, skip, delete, or rewrite a valid existing test merely to make a change pass. Change the test only when the intended contract has deliberately changed.

### Minimum test assessment for every change

Use the applicable items from this list; not every item applies to every change:

- Successful behavior with representative valid input.
- Empty, missing, malformed, boundary, and duplicate input.
- Unauthorized and forbidden behavior for every affected role or permission.
- Loading, empty, offline, timeout, cancellation, retry, and server-error behavior.
- State before and after the action, including cache invalidation and persisted state.
- Cleanup after failure, unmount, sign-out, subscription disposal, or partial upload.
- App restart, background suspension, reconnection, and stale-session behavior when lifecycle matters.
- Accessibility labels, disabled state, form feedback, and user-visible error messages for interactive UI.
- Privacy: sensitive values are not rendered, persisted, logged, or sent in the wrong payload.
- Android and iOS behavior when native APIs or platform differences are involved.

### Tests required by change type

#### Pure logic, types, validators, and mappers

- Add or update a colocated `*.test.ts` file.
- Cover representative valid values, boundary values, malformed values, and deterministic output.
- For canonical roles and permissions, cover every supported alias, unknown roles, explicit denies, and privilege-escalation attempts.
- For state machines, cover every allowed transition and important forbidden transition.

#### React hooks, components, forms, and screens

- Add or update a colocated `*.test.tsx` file when behavior changes.
- Test what the user can see and do: rendering, presses, text entry, validation, submission, disabled/loading states, and error recovery.
- Cover loading, empty, failure, and permission-denied states when the component owns them.
- Verify accessible labels or roles for important actions.
- Do not test private implementation details or duplicate the behavior of React Native itself.

#### Authentication, authorization, routes, and deep links

- Test sign-in success and failure, session restoration, token refresh, sign-out cleanup, inactive profiles, missing profiles, and unsupported roles as applicable.
- Test protected-route redirects and direct deep-link attempts while signed out or unauthorized.
- Test the exact effective permission required for each restricted action.
- Verify that client guards do not imply server authorization and that rejected users cannot see cached protected data.

#### Supabase reads, RPCs, storage, and Realtime

- Unit-test query/RPC payload mapping, returned-data mapping, typed error handling, and cache keys with mocked I/O.
- Add integration checks against a non-production project when RLS, RPC, trigger, schema, or storage-policy behavior changes.
- Test at least one allowed and one denied role for sensitive RLS or RPC behavior.
- Test upload validation, private path construction, failed-transaction cleanup, and signed/private access behavior.
- Test Realtime event mapping, duplicate events, reconnect behavior, and subscription cleanup.
- Regenerate database types after confirmed schema changes and verify the app still type-checks.

#### Gateway, network, and AI jobs

- Test bearer-token headers, endpoint resolution, URL joining, timeout, cancellation, status/error mapping, and redaction of sensitive errors.
- Test a rotated endpoint: safe reads may refresh and retry once; unsafe mutations must not repeat without an idempotency contract.
- Test queued-job states such as queued, running, succeeded, failed, expired, and unavailable when supported by the contract.
- Test bounded backoff, persisted job-ID recovery, app restart/resume, and AI-host outages.
- Verify that model choice and private manager context are not client-controlled when the backend contract forbids them.
- Verify that AI output remains a draft and cannot directly trigger a protected mutation.

#### Mutations and workflow state changes

- Test the successful transition and its cache invalidation or refresh behavior.
- Test stale state, duplicate submission, dependency blocking, invalid lifecycle transitions, authorization failure, and server rejection.
- For reviews, test self-review prevention and primary/backup reviewer rules.
- For sensitive actions, test that an offline request is blocked rather than silently queued.
- Test failure atomicity so partial database, notification, or storage side effects are not presented as success.

#### Files, evidence, receipts, reports, and PDF imports

- Test allowed and rejected file types, maximum size boundaries, sanitized filenames, cancellation, retry, and cleanup.
- Test that private files do not become public URLs and that unauthorized users cannot access metadata or links.
- Test server extraction failures, malformed AI decomposition, editable draft validation, and explicit confirmation before import commit.
- Manually verify document picking, camera/photo permissions, file sharing, and platform-specific URI handling on both platforms when affected.

#### Notifications and navigation from notifications

- Test event-to-notification mapping, unread state, deduplication, token registration updates, and sign-out cleanup.
- Test authorized, unauthorized, deleted, and malformed notification destinations.
- Manually verify foreground, background, and cold-start delivery/deep linking on real devices or suitable simulators when affected.

#### Offline, cache, AppState, and persistence

- Test cached-read behavior, reconnect refresh, stale data indicators, and safe recovery after process restart.
- Test that approvals, finance, permission changes, and other sensitive mutations are never automatically replayed.
- Test corrupt, partial, expired, and oversized persisted values and their cleanup.

#### Lists, filtering, pagination, and Realtime merging

- Test filter and sort rules, empty results, pagination boundaries, deduplication, refresh, and stable identifiers.
- Test how incoming Realtime events merge with currently paged or filtered data.
- Manually verify virtualization and usable scrolling with a realistically large data set.

#### Visual-only, theme, and layout changes

- Add component tests when behavior, conditional rendering, accessibility, or interaction changes.
- Static color, spacing, or typography-token edits do not require a unit test unless a semantic mapping or calculation changes.
- Manually inspect affected screens on representative Android and iOS sizes for clipping, safe areas, keyboard overlap, orientation assumptions, contrast, and touch-target size.

#### Configuration, dependencies, build scripts, and CI

- Run the full quality command after changes to TypeScript, test setup, ESLint, Jest, Expo config, dependencies, scripts, or CI.
- Run the native export verification when Expo configuration, routing, assets, native dependencies, or build behavior changes.
- Test both the intended success case and useful failure output when modifying scripts or CI.
- Inspect dependency and lockfile changes; do not accept unrelated upgrades silently.

#### Bug fixes and refactors

- A bug fix requires a regression test that fails for the old behavior and passes with the fix whenever the behavior is automatable.
- A refactor must preserve existing tests; add tests first if the behavior being preserved was previously uncovered and is consequential.
- Do not mix a behavior change into a refactor without documenting and testing the new contract.

#### Documentation-only changes

- Unit tests are normally not applicable.
- Verify filenames, commands, links, baseline SHAs, contracts, and statements against the repository or authoritative source.
- If documentation describes executable examples, run them when practical.

### Required validation commands

Use the scripts that exist in `package.json`:

- During development, run the directly affected test file, for example: `npm test -- --runTestsByPath src/path/example.test.ts`.
- After any executable source or test change, run `npm run check` to execute lint, TypeScript checking, and the complete Jest suite.
- After routing, Expo configuration, asset, dependency, build-script, or native integration changes, also run `npm run build:verify`.
- For documentation-only changes, inspect the rendered/plain Markdown and verify referenced paths and commands; runtime tests may be marked not applicable.

If a required command cannot be run because credentials, a backend, a simulator, or another dependency is unavailable, do not claim it passed. Report the exact command not run, why it was unavailable, and the next best verification performed.

Every completion report for an implementation must state:

- Tests added or updated, with filenames.
- Commands run and whether they passed.
- Manual checks performed.
- Tests not run or still needed, with reasons.

## Quality bar

A feature is not done because a screen renders. It must include:

- A documented user journey, supported roles, and permission behavior.
- Real data and the authoritative server-side security contract.
- Loading, empty, validation, permission-denied, offline, timeout, retry, and server-error states where relevant.
- Accessible touch targets, labels, keyboard handling, safe areas, and virtualized long lists.
- Correct cache invalidation and Realtime subscription cleanup.
- Upload validation and failure cleanup when files are involved.
- Applicable tests from the testing and verification policy are added or updated in the same change and pass.
- Verification against the shared deployed backend.
- Android and iOS validation, or a documented platform limitation.

For high-risk workflows, test forbidden behavior as well as successful behavior: self-review, unauthorized deep links, dependency bypasses, duplicate submissions, stale tokens, interrupted uploads, rotated gateway URLs, AI outages, and app suspension.

## Decision and collaboration policy

Future agents should challenge unsafe, brittle, or wasteful decisions with concrete reasons and a safer alternative. In particular, flag requests to copy web UI literally, expose secrets, trust client roles, treat mock screens as complete, run the model on the phone, auto-apply AI output, or build the full 70% before contracts stabilize.

Make small, reversible assumptions when they do not change product scope. Ask the user before decisions that materially affect supported roles, the 70/30 feature boundary, offline mutation behavior, production AI hosting, backend/schema ownership, notification infrastructure, store deployment, or final design direction.

Keep planning files synchronized with implemented reality. When a decision becomes final, record it. When a risk is resolved, replace the warning with the actual contract rather than leaving stale guidance.
