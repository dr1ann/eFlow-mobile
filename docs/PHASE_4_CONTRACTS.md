# Phase 4 evidence and review contract notes

Recorded September 8, 2026 after comparing the mobile implementation with web `main` at `042e1a5b240cf667eb3dfa69d263897686de2a04`. The adopted mobile compatibility baseline remains `508aabc8881630b37a62a973645ecb0bb386e99e` until the full upstream-update procedure and deployed verification are complete.

## Attempt selection and metadata

- `listTaskSubmissions` orders task attempts by descending version. Mobile may review only its newest row when that row is `pending`; an older pending row cannot become actionable.
- `Subtask.latestSubmissionId` identifies the authoritative attempt. Mobile resolves that exact record before exposing a subtask decision.
- Parent attachment reads require both `task_id` and the selected non-null `submission_id`. Mobile no longer has a read path that intentionally mixes attachments across task attempts.
- Subtask attachment reads require the selected `submission_id`. File paths stay inside signing/opening calls and are never rendered.

## Private evidence opening

- `get_task_evidence_rules` supplies the private bucket and server-recommended signed-link lifetime.
- On every explicit Open press, mobile requests rules, creates a fresh signed URL through private Storage, and passes it to `expo-linking` for the native system handler.
- The signed URL is never placed in React state, TanStack Query, SecureStore, logs, or an error message. Cancellation and failed/expired/unavailable opens are redacted and retryable.
- Presentation requires the local `evidenceRules` and `evidenceSignedRead` capability checks. Storage/RLS remains the authorization boundary.

## Review and rework lifecycle

- Task and subtask decision RPCs remain online-only and server-authorized. Client stored-reviewer and self-review checks improve UX but never grant access.
- Requested changes requires nonblank feedback before the decision action is enabled; both actions and the feedback field lock while a decision mutation is pending.
- The confirmed parent rework sequence is `changes_requested → in_progress → submit_task_for_review`. Mobile labels the transition Resume work and does not attempt direct parent resubmission from `changes_requested`.
- An assigned contributor can submit a subtask from `changes_requested`; the interface labels that action Resubmit for review. Versioned server rows preserve earlier evidence and feedback.

## Remaining acceptance evidence

Automated controlled-fake coverage validates version selection, selected-attempt filtering, blank-note pre-upload rejection, fresh signed opening, redacted failures, retry, history display, and pending decision controls. It does not prove deployed RLS/RPC behavior or native file associations. Before the defense, record a non-production contributor → reviewer changes request → version 2 → approval loop, the parent handoff, self/wrong-reviewer denial, unrelated-file denial, and PDF/image opening on both Android and iOS.
