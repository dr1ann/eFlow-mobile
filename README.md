    # eFlow Mobile

Cross-platform eFlow client built with Expo, React Native, TypeScript, Supabase, and the authenticated eFlow control gateway.

Phase 0 supplies the native shell, authentication, role and permission resolution, Supabase client, gateway health check, Realtime helpers, design tokens, and quality tooling. Tasks, evidence, reviews, notifications, and AI workflows begin in later phases.

## What you need

- A current Node.js LTS release (Node 22.17 was used to verify this project).
- A physical Android or iOS device with [Expo Go](https://expo.dev/go) installed.
- The phone and development computer on the same local network.
- A non-production Supabase project and test accounts. Do not use production credentials for Phase 0 testing.

Expo Go is sufficient for the current app. You do not need Android Studio, Xcode, a custom development build, EAS Build, or an on-device AI model.

## Configure the test environment

1. Create a local environment file. It is ignored by Git.

   ```powershell
   Copy-Item .env.example .env
   ```

   On macOS or Linux:

   ```sh
   cp .env.example .env
   ```

2. Set these public client values in `.env`:

   ```dotenv
   EXPO_PUBLIC_SUPABASE_URL=https://your-test-project.supabase.co
   EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-public-anon-or-publishable-key
   ```

   These values are intentionally public to the mobile bundle. Never add a service-role key, database URL, SMTP credential, Cloudflare credential, or AI/Ollama credential.

3. Prepare test data in the non-production Supabase project:

   - An Auth user with an active `profiles` row and a supported role.
   - Role-permission records readable by that user.
   - For gateway testing, a reachable authenticated gateway URL in `system_config.ai_endpoint`.

   Prepare additional accounts or profile states for inactive, missing, malformed, and unsupported-role access checks. Use a role that has the restricted navigation permission when testing the access-check route.

4. Restart Metro whenever `.env` changes. Expo inlines `EXPO_PUBLIC_` values into the bundle at startup.

   To test a gateway at a local/private HTTP address during development only, uncomment `EXPO_PUBLIC_ALLOW_INSECURE_LOCAL_GATEWAY=true`. This never permits HTTP in a production build; use HTTPS for any shared or deployed environment.

## Install and run

From the repository root:

```sh
npm ci
npm start
```

`npm ci` installs exactly the versions recorded in `package-lock.json`. Use `npm install` only when intentionally changing dependencies.

When Metro displays its QR code:

- **Android:** open Expo Go and scan the QR code.
- **iOS:** scan the QR code with the Camera app, then open it in Expo Go.

If the app shows a configuration error, recheck `.env` and restart `npm start`. If the device cannot connect, confirm that both devices use the same network and that the computer firewall permits the Expo development server.

Expected first-run behavior:

1. The sign-in screen appears when no session exists.
2. A valid active account opens Home and Settings.
3. The Home screen can run **Check gateway health** when the test gateway is configured.

## Phase 0 manual acceptance checklist

Perform these checks on Android and iOS before treating Phase 0 as manually accepted:

- [ ] The app starts in Expo Go without a red error screen.
- [ ] A valid active employee account signs in and can open Home and Settings.
- [ ] Invalid credentials show an understandable error and do not open protected content.
- [ ] Closing and reopening the app restores the signed-in session.
- [ ] Signing out removes protected content; signing in as another account does not show the previous user's name or permissions.
- [ ] Missing, inactive, malformed, and unsupported-role profiles receive a useful access-denied message.
- [ ] A direct attempt to open a protected route while signed out or rejected does not reveal protected or cached data.
- [ ] Each supported role exposes only its permitted navigation and actions. Users without the required permission cannot open the access-check route.
- [ ] Updating a test profile's active state, role, or permission override while the app is foregrounded refreshes access safely.
- [ ] **Check gateway health** succeeds against the authenticated test gateway and shows a useful message when offline or unreachable.
- [ ] Sign-in fields and buttons have usable screen-reader labels, adequate touch targets, correct safe areas, and no keyboard overlap.
- [ ] Light and dark mode layouts have no clipped text or inaccessible tab controls.

The current app intentionally does not test Phase 1 task, evidence, submission, review, announcement, or notification workflows.

## Quality checks

Run these after executable changes:

```sh
npm run check
npm run build:verify
```

`npm run check` runs ESLint, TypeScript, and the full Jest suite. `npm run build:verify` performs Android and iOS native bundle exports. To inspect Expo configuration and dependency health, run:

```sh
npx expo-doctor
npx expo install --check
```

## Database types

The repository includes a bootstrap database contract for the audited Phase 0 tables. Replace it with generated types after obtaining the non-production project reference and authenticating the Supabase CLI:

```powershell
$env:SUPABASE_PROJECT_REF = "your-test-project-ref"
npm run supabase:types
```

The project reference is not a secret. Do not place server-only credentials in `.env`, source code, screenshots, or documentation.

## References

- [Mobile implementation phases](MOBILE_IMPLEMENTATION_PHASES.md)
- [Phase 0 implementation plan](PHASE_0_IMPLEMENTATION_PLAN.md)
- [Audited web baseline and contract notes](docs/WEB_BASELINE.md)
- [Feature parity matrix](docs/FEATURE_PARITY_MATRIX.md)
