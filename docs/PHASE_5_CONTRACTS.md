# Phase 5 work-discovery contract record

## Status

- Status: P5.1–P5.4 are implemented locally; live RLS and Android/iOS acceptance are open.
- Recorded: September 15, 2026.
- Adopted web compatibility baseline: `508aabc8881630b37a62a973645ecb0bb386e99e`.
- Latest upstream `main` rechecked: `042e1a5b240cf667eb3dfa69d263897686de2a04`; it remains the inspected, not adopted, SHA.

The `508aabc..042e1a5b` comparison adds evidence security, project completion, and cash-release schedule migrations. It does not replace the existing work-discovery read contract. Finance remains outside Phase 5.

## Implemented read contract

| Journey | Mobile behavior | Authorization boundary |
| --- | --- | --- |
| My Tasks | `tasks` is restricted by the existing assignment/team/effective-lead ownership filter, persisted status is applied before the 30-row range, and rows use stable deadline/ID ordering. | `tasks` RLS decides which rows exist for the session. |
| My Subtasks | `subtasks` is queried by direct `assigned_to` or `assigned_to_ids`; no parent-task team membership is imposed by mobile. Persisted status is applied before pagination and ordering ends with `id`. | `subtasks` RLS remains authoritative; see the assignee-only probe below. |
| Work I am Leading | The leading filter keeps effective Task Lead precedence: `assigned_to`, then `recommendation_lead_id` only while unassigned. | RLS and the persisted relation, not a role label or recommendation display, decide visibility/authority. |
| Status filters | Active, Waiting for assignment, Awaiting review, Changes requested, Completed, and History map to persisted status values in the query before paging. The app does not claim dependency-blocked state from a partial page. | Server state is the source of truth; Phase 7 owns authoritative readiness recovery. |
| Deadlines | Date-only values are local device calendar dates. Timestamps are converted to the device's local calendar date. Overdue and Due in 7 days filter loaded authorized pages and display loaded counts as partial. | No client deadline view is presented as an organization total or as server reminder timing. |
| Project drill-down | Project detail queries `tasks.linked_project_id` only, excludes soft-deleted tasks, and uses stable due-date/ID order. A task links back only through its mapped canonical UUID. | Both task and project destinations re-fetch under RLS. Missing/deleted/hidden records share generic unavailable UI. |

`project_id` stays mapped only as a legacy compatibility/display field: proposal-decomposition rows may hold a non-UUID hierarchy slug. It must never be used to construct a project route or project task filter.

## User-visible recovery behavior

- Every work feed has virtualized rows, pull-to-refresh, an explicit accessible load-more control, loading, retryable error, cached refresh-failure, and paused/offline states.
- An empty deadline-filtered loaded page with another raw page available says so and retains Load more; it does not claim that no later authorized match exists.
- Task navigation, subtask navigation, submission history, and progress history retain the existing guarded destination reads.
- Project work is not queried or rendered for a user without `navigation.tasks`; project navigation from a task is hidden without `navigation.projects`.

## Required non-production and device evidence

The [Project 5 test setup](sql/phase-5-project-5-test.md) provides a rerunnable SQL fixture using `kurt@gmail.com` as contributor, with pagination/deadline cases and real parent workflow states. It prepares data; it does not mark any live or device acceptance item passed.

Before marking Phase 5 accepted, record sanitized outcomes for:

1. A contributor assigned only at subtask level, including a case where they are not in the parent task's client-visible team list. The deployed policy currently appears to reach subtask reads through `can_see_task`, so this must be an allowed/denied RLS probe or an approved backend change; mobile must not bypass it.
2. An actual Task Lead, a stale recommendation that has been superseded by `assigned_to`, a reviewer entering the existing review inbox, and an unrelated/inactive account denial.
3. Later-page status/deadline matches, duplicate/moving rows, a refresh failure with cached data, and no-data/offline behavior.
4. Task → project and project → task links for an allowed record plus deleted/RLS-hidden task and project destinations.
5. Local-midnight deadline behavior on the demonstrated Android and iOS devices, plus practical scrolling/touch-target inspection with a realistically large list.

Do not use a service-role key, disable RLS, make a bucket public, or infer deployment acceptance from enabled local capabilities.
