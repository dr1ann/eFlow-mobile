# Project 6: three-subtask standalone test

Run the whole [SQL setup](phase-6-project-6-standalone-test.sql) in your non-production Supabase SQL Editor as `postgres`. It creates one new **[P6 TEST] Three-step standalone practice** task under **Project 6**, with exactly three sequential subtasks assigned to **kurt@gmail.com**. The parent is in progress; all subtasks start at To do, 0%. There are no deadlines. Existing project work is preserved, and rerunning does not reset your test changes.

The existing active Task Lead is **gabzcah@gmail.com** and the parent reviewer is **bplo.head@gmail.com**. Their existing permissions must allow the operations. This controlled setup uses the same authenticated creation/start RPCs and subtask INSERT/RLS pattern as the supplied Phase 5 sample; it does not establish that mobile task creation is ready.

For the test build, the relevant capabilities are Phase 2 `subtaskExecutionRules` and Phase 1 `subtaskProgress`. Do not replace other enabled values. A capability flag does not grant database permission.

| Step | What to do | Expected result |
| --- | --- | --- |
| 1 | Kurt: open step 3 and try saving 10% progress while steps 1 and 2 remain incomplete. | Server rejects the attempt because earlier sequential work is incomplete. Step 3 stays To do, 0%. |
| 2 | Gabriel: open the parent task → Plan subtasks → step 3 → Make standalone. Refresh. | Step 3 shows Standalone and stays To do, 0%. |
| 3 | Gabriel: before Kurt starts it, choose Make sequential. Kurt refreshes and tries 10% again. | Sequential dependency blocking returns. No progress is saved. |
| 4 | Gabriel: choose Make standalone again. Kurt refreshes and saves 10%. | Step 3 becomes In progress, 10%, while steps 1 and 2 remain incomplete. |
| 5 | Gabriel: refresh planning and inspect step 3. | Mode controls are unavailable because work has started. Steps 1 and 2 remain sequential. |

Use **All dates** to find this undated fixture. The app starts a subtask through **Update progress**; a separate Start button is not required. Do not complete or approve steps 1 or 2 during this test. Refresh after switching accounts or changing execution mode.

The setup is one transaction. Missing/duplicate identities or projects, rejected RPCs, and denied inserts roll it back. If the SQL Editor leaves an aborted transaction open after an error, run `ROLLBACK;` before retrying. No live SQL was executed by Codex.

Source check: upstream `main` remains `46e6f520c5e4dcd71c4e6ae40610518079b71b7c`. Comparing the adopted baseline `508aabc8881630b37a62a973645ecb0bb386e99e` found three added migrations (evidence security, cash-release scheduling, and project completion); the task-create and sequential/standalone contracts used here are unchanged. Real backend and device acceptance remain required.

## Preparation checks — September 17, 2026

- Added and ran temporary `verify-phase6-seed.mjs` in the existing isolated PGlite harness at `C:/Users/james/AppData/Local/Temp/eflow-phase5-seed-verification-20260917`. All 11 scenarios passed: initial records/actors/context, preserving progress on rerun, partial fixture preservation, missing/inactive/duplicate contributor, duplicate project, archived/invalid-status project, denied INSERT, and rollback after a late INSERT failure. Controlled routine/policy doubles verify script behavior, not deployed authorization or workflow correctness.
- `npm run check`: passed lint, TypeScript, and all 78 Jest suites / 258 tests. No app test files changed for this SQL fixture.
- `git diff --check`: passed. Manually checked account/project names against the pasted sample, SQL payloads against source, and test steps against the mobile progress/planning controls.
- Supabase execution and physical Android/iOS checks were not performed; the user must run the fixture and steps above in their test environment. `npm run build:verify` was not rerun because this change adds only SQL/documentation and does not affect native source, routing, configuration, assets, or dependencies.
