# Phase 0 Implementation Plan — Mobile Foundation

## Plan status

- Status: Implemented locally; awaiting deployed Supabase credentials, test accounts, and Android/iOS verification
- Current phase: Phase 0 — Mobile foundation
- Repository state when planned: Planning documents only; Git is not initialized
- Source roadmap: `MOBILE_IMPLEMENTATION_PHASES.md`
- Web audit baseline: `0ecffafffc1fc06b5c12b66014301e78aa659cde`
- Plan created: August 25, 2026

## Outcome

Phase 0 will deliver one complete foundation workflow:

```text
Cold app launch
  -> restore or establish a Supabase session
  -> load the authoritative profile, canonical role, and effective permissions
  -> reject an inactive, missing, or unknown-role profile
  -> enter the protected native shell
  -> perform an authenticated Supabase read
  -> perform an authenticated gateway health request
  -> sign out and remove user-scoped state
```

The result is a tested Android and iOS foundation for Phase 1. Phase 0 does not include task, review, project, notification, push, chat, budget, or AI product workflows.

## Planning decisions

1. Use the current stable Expo SDK available when implementation begins, TypeScript in strict mode, and Expo Router. Install Expo-managed dependencies with `npx expo install` so versions match the selected SDK.
2. Use `src/app/` as a routes-only directory because this is a new project. Keep screens, components, contracts, providers, and utilities outside the route tree.
3. Use Expo Router protected routes for session and permission guards. Guards improve navigation and UX; Supabase RLS, RPC authorization, and gateway authorization remain authoritative.
4. Use TanStack Query for remote server state. Keep authentication bootstrap state small and separate, and do not add a general-purpose global state library in Phase 0.
5. Keep the query cache in memory during Phase 0. Do not persist private API results until a later feature demonstrates a safe offline requirement.
6. Use the Supabase publishable/anon key only. It is allowed in the client bundle; service-role and other server-only credentials are forbidden.
7. Protect the persisted Supabase session with a chunked Expo SecureStore adapter. This keeps all session material inside the platform secure store while avoiding per-item size limits.
8. Resolve the gateway through the authoritative Supabase configuration contract. Normalize and validate the returned absolute URL; allow insecure HTTP only for an explicit local-development configuration.
9. Retry a request after gateway endpoint refresh only when it is safe: idempotent reads by default, or mutations whose backend contract supports an idempotency key. Never blindly replay a sensitive mutation.
10. Treat unrecognized roles, missing permissions, invalid runtime configuration, and malformed server responses as deny-by-default failures with useful non-sensitive messages.

Current implementation references:

- [Expo Router authentication and protected routes](https://docs.expo.dev/router/advanced/authentication/)
- [Expo Router common navigation patterns](https://docs.expo.dev/router/basics/common-navigation-patterns/)
- [Supabase Auth with React Native](https://supabase.com/docs/guides/auth/quickstarts/react-native)
- [Supabase JavaScript client initialization and React Native storage](https://supabase.com/docs/reference/javascript/initializing)
- [Supabase React Native token-refresh lifecycle](https://supabase.com/docs/reference/javascript/auth-startautorefresh)
- [TanStack Query for React Native](https://tanstack.com/query/latest/docs/framework/react/react-native)

## Prerequisites and contract gates

These inputs are required before the relevant work package can be completed. They must be obtained without committing secrets.

- Access to the current upstream web repository and deployed Supabase project.
- The current upstream `main` SHA. Compare it with the recorded baseline before adopting schema, role, permission, profile, gateway-config, or health-check contracts.
- The Supabase project URL and public publishable/anon key for local environment configuration.
- Supabase CLI access capable of generating database types without placing privileged credentials in the repository.
- Confirmed deployed contracts for:
  - current-user profile lookup;
  - active/inactive account state;
  - canonical roles, known aliases, and effective permissions;
  - the published gateway endpoint source in `system_config` or its replacement;
  - the authenticated gateway health route and response schema.
- Test accounts covering an active normal user, an inactive user, a missing-profile user, and at least two distinct permission sets.
- A supported Android target and an iOS device/build path. The current Windows host cannot perform local iOS Simulator validation, so iOS verification will require a physical device or an approved remote/macOS build path.

If an upstream or deployed contract differs from the roadmap, record the difference before coding and update this plan, the parity matrix, and the baseline only after compatibility is verified.

## Target project layout

Only route files and layouts belong under `src/app/`.

```text
assets/
docs/
  adr/
  FEATURE_PARITY_MATRIX.md
  WEB_BASELINE.md
scripts/
src/
  app/
    (auth)/
      _layout.tsx
      sign-in.tsx
    (protected)/
      (tabs)/
        _layout.tsx
        index.tsx
        settings.tsx
      _layout.tsx
    +not-found.tsx
    _layout.tsx
  components/
    app-screen.tsx
    button.tsx
    form-field.tsx
    status-notice.tsx
  contracts/
    database.types.ts
    gateway.ts
    permissions.ts
    profile.ts
    roles.ts
    runtime-config.ts
  features/
    auth/
      api/
      components/
      hooks/
      screens/
      auth-state.ts
      role-mapper.ts
    shell/
      screens/
  lib/
    config/
    gateway/
      client.ts
      endpoint-resolver.ts
      errors.ts
    query/
      client.ts
      keys.ts
      lifecycle.ts
    supabase/
      client.ts
      realtime.ts
      session-lifecycle.ts
      session-storage.ts
  providers/
    app-providers.tsx
  theme/
    colors.ts
    tokens.ts
    typography.ts
  test/
    fixtures/
    setup.ts
app.config.ts
eas.json
eslint.config.js
package.json
tsconfig.json
```

Feature directories for Phase 1 may be added when their first real vertical workflow begins. Empty speculative `tasks`, `reviews`, `projects`, and similar modules are not needed in Phase 0.

## Work packages

### P0.1 — Baseline, repository, and contract inventory

Purpose: create a safe starting point before app code depends on upstream behavior.

Implementation:

- Initialize Git and preserve the existing planning documents in the initial history.
- Add a mobile-appropriate `.gitignore`, `.env.example`, and repository README.
- Fetch or inspect upstream `main`, compare it with `0ecffafffc1fc06b5c12b66014301e78aa659cde`, and review Phase 0 contract changes in this order:
  1. schema, RLS, RPCs, views, and storage policies;
  2. FastAPI authentication, runtime endpoint publication, and health route;
  3. role names, aliases, profile activation, and effective permissions;
  4. shared pure types and mappers;
  5. UI-only changes last.
- Create `docs/WEB_BASELINE.md` with the audited SHA, comparison date, relevant contract notes, and known compatibility risks.
- Create `docs/FEATURE_PARITY_MATRIX.md` with at least: journey, mobile phase, web status, live contract, supported roles, mobile status, evidence, and notes.
- Record unresolved contract questions rather than guessing table names, permission keys, or gateway paths.

Acceptance:

- Git reports a clean, initialized repository after the baseline commit.
- The current upstream SHA and comparison result are recorded.
- Every contract used later in Phase 0 has an authoritative source or an explicit blocker.
- No secret or privileged connection string is present in tracked files.

### P0.2 — Expo scaffold and quality commands

Purpose: establish a reproducible, strict, buildable native project.

Implementation:

- Scaffold Expo with TypeScript and Expo Router in the existing repository without removing the planning files.
- Configure `src/app`, the `@/* -> src/*` path alias, strict TypeScript settings, and platform metadata.
- Add only Phase 0 dependencies:
  - Supabase JavaScript client and required React Native URL/runtime support;
  - Expo SecureStore plus the selected encrypted-session storage dependency;
  - TanStack Query and React Native network-state integration;
  - runtime schema validation for environment and gateway payloads;
  - the Expo-compatible unit/component test stack.
- Add package commands for start, Android, iOS, lint, type-check, unit tests, watch tests, build/export verification, and the full CI check.
- Add CI that installs from the lockfile and runs lint, type-check, unit tests, and headless Android/iOS bundle or export verification.
- Keep local `.env` files ignored and document only these public client variables initially:
  - `EXPO_PUBLIC_SUPABASE_URL`;
  - `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- Fail startup with a useful configuration screen in development when required public variables are missing or invalid; do not print secret or token values.

Acceptance:

- A clean checkout installs from the lockfile.
- Lint, type-check, test, and build-verification commands run independently and through one CI command.
- The root route renders on Android and produces an iOS bundle/export.
- `src/app` contains route files only.

### P0.3 — Design tokens, primitives, and provider shell

Purpose: prevent feature code from coupling to the unfinished web design.

Implementation:

- Define semantic light/dark color tokens, spacing, sizing, typography, radius, elevation, motion, focus, disabled, success, warning, and error tokens.
- Build only the shared primitives required by Phase 0: safe-area screen, button, text input/form field, loading state, and status notice.
- Meet accessible touch-target, contrast, labeling, dynamic-type, keyboard, and reduced-motion expectations.
- Compose root providers in a stable order:

```text
native prerequisites and splash coordination
  -> theme and safe area
  -> authentication/session
  -> TanStack Query
  -> Expo Router navigators
```

- Keep each provider independently testable and ensure subscriptions/listeners return cleanup functions.

Acceptance:

- Sign-in, bootstrap, error, and protected-shell states use shared semantic tokens.
- Light and dark modes remain readable at enlarged text sizes.
- Provider listeners are registered once and cleaned up in tests.

### P0.4 — Typed Supabase client and secure session lifecycle

Purpose: establish the authenticated Supabase boundary used by every later phase.

Implementation:

- Generate `src/contracts/database.types.ts` from the deployed schema and add a repeatable generation command. Never hand-edit generated output.
- Create one typed Supabase client with the project URL, public publishable key, `persistSession`, `autoRefreshToken`, URL-session detection disabled for native, and the approved storage adapter.
- Implement the chunked secure-session adapter:
  - split serialized session values into bounded Expo SecureStore entries;
  - commit secure metadata only after every chunk is written;
  - handle missing/corrupt data by clearing it and returning a recoverable signed-out state;
  - remove all reachable chunks and metadata on explicit local credential reset.
- Register one React Native `AppState` listener that starts token refresh while active and stops it while inactive.
- Implement a session provider with explicit states: `booting`, `signedOut`, `loadingAccess`, `authorized`, and `rejected`.
- On session establishment, call the confirmed profile/effective-permissions contract and validate the response at runtime.
- Reject missing, inactive, malformed, or unknown-role profiles without exposing private server details. Provide retry and sign-out actions.
- On sign-out or user change, unsubscribe Realtime channels, clear user-scoped queries and gateway endpoint cache, then end the Supabase session.

Acceptance:

- Sign-in succeeds with the deployed authentication method.
- A valid session restores after a full app restart on Android and iOS.
- Refresh starts/stops with app state and stale/invalid sessions return to sign-in cleanly.
- Inactive, missing-profile, malformed-profile, and unknown-role cases show useful deny-by-default states.
- Sign-out prevents the previous user's cached data from appearing in the next session.

### P0.5 — Canonical roles, permissions, and protected routing

Purpose: make direct navigation and deep links follow the same access model as visible navigation.

Implementation:

- Derive the canonical role union and alias table from the verified deployed/web contract. Keep normalization in one pure, tested mapper.
- Represent effective permissions as server-returned data where available. Do not infer elevated permission solely from a UI role label.
- Add pure access evaluators for authenticated, active-profile, canonical-role, and required-permission checks.
- Configure the root Expo Router stack with protected route groups for:
  - signed-out routes;
  - profile-rejected recovery;
  - authenticated and active-profile routes.
- Guard role/permission-sensitive screens again at their nested layout or screen registration. Navigation links should use the same policy evaluator.
- During bootstrap, keep the native splash/loading state visible instead of briefly rendering the wrong route.
- Add a not-found route that returns the user to the first authorized destination.
- Preserve the requested deep-link destination only when it is valid and authorized after session restoration; otherwise use a safe anchor and explain the denial when appropriate.
- Add a Phase 0 route-policy test fixture using one confirmed real permission so insufficient-permission deep links can be tested without inventing a product role.

Acceptance:

- Signed-out deep links to protected routes land on sign-in.
- An active but insufficiently permitted user cannot open a restricted route by URL, history, or programmatic navigation.
- A newly forbidden active screen is removed when permissions/session state changes.
- Unknown roles and permissions fail closed.
- Unit tests cover every known persisted role alias, canonical value, and unknown input.

### P0.6 — TanStack Query and Realtime foundation

Purpose: provide predictable server-state and foreground-update behavior for Phase 1.

Implementation:

- Create one QueryClient with documented defaults:
  - retry safe reads only for transient failures;
  - do not retry authentication, authorization, validation, or not-found failures;
  - do not retry mutations by default;
  - use bounded stale and garbage-collection times;
  - disable sensitive error/body logging.
- Connect TanStack Query focus state to React Native `AppState` and online state to the network-state provider.
- Add typed query-key factories scoped by feature and current user/organization where required.
- Provide one profile/access query and a shell-level authenticated Supabase smoke query using the confirmed live contract.
- Create Realtime helpers that use deterministic channel names, expose typed event callbacks, avoid duplicate subscriptions, report channel errors, and always remove channels on unmount, sign-out, or user change.
- Do not treat Realtime as background push and do not persist the Query cache in Phase 0.

Acceptance:

- Going offline yields a distinct recoverable state rather than repeated request loops.
- Returning online or active refreshes eligible stale reads once.
- Signing out clears all user-scoped queries and Realtime channels.
- Tests prove listener and subscription cleanup.

### P0.7 — Typed gateway client and rotating endpoint recovery

Purpose: create a safe, reusable boundary for the eFlow FastAPI gateway.

Implementation:

- Define runtime-validated health-request and health-response contracts from the verified gateway route.
- Implement an endpoint resolver that:
  - reads the published endpoint from the confirmed Supabase contract;
  - requires an absolute URL;
  - normalizes path joining and trailing slashes;
  - rejects credentials, fragments, unexpected protocols, and malformed URLs;
  - caches the normalized URL in memory;
  - can force one refresh after a stale-tunnel failure.
- Implement a gateway client that:
  - obtains the current access token immediately before each request;
  - sends it as a bearer token without logging it;
  - supports caller cancellation and a bounded timeout;
  - distinguishes configuration, offline/network, timeout, cancellation, authentication, authorization, HTTP, and response-validation errors;
  - limits response size where the runtime permits;
  - refreshes the endpoint and retries once only under the safe retry policy.
- Do not call the private AI service or Ollama directly and do not add a generic prompt endpoint.
- Add a protected shell action or status panel that performs the authenticated gateway health request and exposes loading, success, timeout, offline, unauthorized, unavailable, and retry states.

Acceptance:

- A signed-in user can complete the deployed authenticated health request.
- Missing/invalid configuration, rotated endpoint, timeout, cancellation, offline, 401, 403, 5xx, and malformed-success responses map to deterministic typed errors.
- A stale endpoint causes at most one resolver refresh and one safe retry.
- Tests assert that bearer tokens and sensitive bodies never reach logs or user-facing raw errors.

### P0.8 — Integrated foundation slice, hardening, and handoff

Purpose: prove the exit criteria as one workflow rather than a set of disconnected modules.

Implementation:

- Complete the protected home shell with account identity, canonical role, connectivity state, authenticated Supabase-read state, and gateway-health state. Do not add mock dashboards.
- Add unit/component tests for storage, role mapping, permission evaluation, auth state transitions, query retry classification, endpoint resolution, gateway errors, and subscription cleanup.
- Add integration tests around Supabase and gateway adapters using injected fakes, plus a documented manual test pass against the deployed backend.
- Test forbidden paths: unauthenticated deep link, insufficient-permission deep link, inactive user, missing profile, unknown role, stale token, corrupt session storage, rotated endpoint, AI/gateway outage, and app background/foreground transitions.
- Scan source, tracked files, generated bundles/source maps, logs, and screenshots for server-only credentials or test-user secrets.
- Run the complete verification command, Android device/emulator validation, iOS device/build validation, and cold-restart session restoration on both platforms.
- Update `MOBILE_IMPLEMENTATION_PHASES.md`, the baseline record, and parity matrix with implemented reality. Mark Phase 0 complete only after every exit criterion has evidence.

Acceptance:

- All roadmap Phase 0 exit criteria pass against the shared deployed backend.
- CI is green from a clean install.
- Android and iOS results are recorded, including any approved limitation.
- No unresolved high-severity security, authorization, session-restoration, or secret-leakage issue remains.

## Test matrix

| Area | Unit/component evidence | Deployed/manual evidence |
| --- | --- | --- |
| Environment | Required/malformed variables fail safely | Production-like build starts with public config only |
| Session storage | Round trip, corruption, missing key, delete | Cold restart restores; sign-out removes access |
| Auth lifecycle | Sign-in, refresh, expiry, sign-out state transitions | Real valid and stale sessions |
| Profile access | Active, inactive, missing, malformed | Dedicated test accounts |
| Roles | Every canonical role/alias and unknown input | Returned role matches deployed account |
| Permissions | Allow/deny and state-change evaluation | Two accounts with distinct effective permissions |
| Routing | Signed-out, rejected, allowed, forbidden deep links | Platform deep-link launch while cold and warm |
| Supabase | Typed query success and error mapping | One authenticated live read under RLS |
| Query lifecycle | Offline, retry classification, focus/online refresh | Airplane mode and foreground recovery |
| Realtime | Subscribe, deduplicate, error, cleanup | One allowed live change while app is active, if the confirmed Phase 0 contract is published to Realtime |
| Gateway | URL validation, timeout, cancel, 401/403/5xx, bad payload, rotation | Authenticated health request and tunnel-rotation drill |
| Privacy | Redaction and cache clearing | Bundle/log/source-map secret scan |
| Platforms | Rendering and accessibility checks | Android and iOS sign-in/restart/sign-out pass |

## Phase 0 exit checklist

- [ ] Expo/TypeScript application is scaffolded and committed.
- [ ] CI, lint, type-check, test, and build/export verification pass.
- [ ] Public configuration is validated and server-only secrets are absent.
- [ ] Deployed Supabase database types are generated reproducibly.
- [ ] User can sign in, restore a session after restart, refresh, and sign out.
- [ ] Missing, inactive, malformed, and unknown-role profiles are rejected clearly.
- [ ] Canonical role and effective permissions resolve from the authoritative contract.
- [ ] Direct deep links cannot bypass session or permission guards.
- [ ] One authenticated Supabase query succeeds under deployed RLS.
- [ ] One authenticated gateway health request succeeds.
- [ ] Gateway timeout, cancellation, typed errors, endpoint refresh, and safe one-retry behavior are verified.
- [ ] Query focus/online lifecycle and Realtime cleanup are tested.
- [ ] Theme tokens and accessible Phase 0 primitives work in light/dark modes.
- [ ] Web baseline and feature parity matrix reflect verified reality.
- [ ] Android and iOS validation evidence is recorded.

## Suggested implementation sequence and review boundaries

Keep changes small and reviewable. A practical sequence is:

1. Baseline audit, Git initialization, scaffold, configuration, and CI.
2. Theme primitives, provider shell, typed Supabase client, and generated database types.
3. Encrypted session persistence, auth bootstrap, profile/access loading, and sign-out cleanup.
4. Canonical role mapper, permission evaluator, protected routes, and deep-link tests.
5. TanStack Query lifecycle, authenticated Supabase read, and Realtime helpers.
6. Gateway endpoint resolver, typed client, health integration, and rotation tests.
7. Cross-platform integrated test pass, secret scan, parity/baseline updates, and Phase 0 sign-off.

Do not begin Phase 1 task screens until the integrated foundation slice meets the exit checklist. If a backend contract blocks one item, keep Phase 0 open and document the exact owner and missing contract rather than replacing it with mock data.

## Main risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Upstream changed after the recorded audit | Compare current `main` before adopting any Phase 0 contract; update the baseline only after verification. |
| SecureStore cannot safely hold a large serialized session | Split the session into bounded SecureStore-only chunks and test large and corrupt payloads on both platforms. |
| Role labels and persisted values drift | One deny-by-default canonical mapper generated from verified contracts, with an exhaustive alias test table. |
| Client route guards are mistaken for security | Treat guards as UX only and test the same forbidden reads against RLS/gateway authorization. |
| Rotating tunnel causes duplicate mutations | Automatic retry is idempotent-only unless the backend accepts an idempotency key. |
| Quick Tunnel or AI host is unavailable | Surface gateway status separately and ensure the Supabase-backed shell remains usable. |
| Cached data crosses user sessions | Scope query keys and clear queries, endpoint state, and Realtime subscriptions on sign-out/user change. |
| Windows host hides iOS defects | Require a physical iOS or approved remote/macOS validation pass before Phase 0 sign-off. |
| Public and private environment values are confused | Maintain an allowlisted public-variable schema, ignored local env files, CI/bundle scans, and no privileged keys in mobile tooling. |
