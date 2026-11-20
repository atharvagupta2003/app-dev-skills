# Skill index

One line per skill, grouped in four. Keep this in step with `skills/`: every folder under `skills/` has one row here, and every row links to a real folder.

## Mobile client

| Skill | What it covers |
|---|---|
| [expo-app-start-performance](skills/expo-app-start-performance/SKILL.md) | Measure and speed up an Expo cold start: in app stage markers in the native log, saved home data shown first, per user saved copies, parallel start reads, bounded waits and what to clear. |
| [expo-router-route-gate](skills/expo-router-route-gate/SKILL.md) | A fail closed route gate for Expo Router driven by the user's place or mode, with a test that checks every navigation target in the source, safe Back and redirect loop rules, onboarding resume points derived from answers after a step reorder, and step counters that count only the steps shown. |
| [react-native-android-keyboard](skills/react-native-android-keyboard/SKILL.md) | Keep buttons, pinned footers and focused fields above the soft keyboard on edge to edge Android, measure only nodes that no animation moves, and verify it on a device. |
| [react-query-in-react-native](skills/react-query-in-react-native/SKILL.md) | TanStack React Query in React Native: typed keys, a per user persisted cache, online and focus wiring, invalidation, and test client defaults wrapped so no query can keep a Jest run from exiting. |
| [offline-outbox-and-sync](skills/offline-outbox-and-sync/SKILL.md) | A device outbox with idempotency keys, batched flushes, backoff, rate limits that wait for the server's reset time, dropping invalid items, and safe late merges. |
| [media-upload-pipeline](skills/media-upload-pipeline/SKILL.md) | Photo uploads that strip all metadata on the device, verify the whole JPEG on the server, bind the check to the stored version, and keep private media behind short signed links. |
| [expo-local-android-builds](skills/expo-local-android-builds/SKILL.md) | A local Android release APK build when cloud minutes run out, with secret handling, a separate worktree, same-signature upgrade installs, and a launch and crash log check before saying it is ready. |

## Supabase and Postgres

| Skill | What it covers |
|---|---|
| [supabase-migrations-discipline](skills/supabase-migrations-discipline/SKILL.md) | Migrations as the only route to the database, declarative schema files with a diff gate, enum values in their own migration, two-step signature changes with defaults, database before functions with a fail closed window, counting destructive selections before deploy, idempotent data fixes, backfills inside the migration when a rule loosens, and a grants check. |
| [supabase-rls-and-function-access](skills/supabase-rls-and-function-access/SKILL.md) | Row level security on every table, members reading sensitive data only through functions that take identity from the session, safe security definer functions, and closed vocabularies with no else branch that grants. |
| [postgres-concurrency-and-limits](skills/postgres-concurrency-and-limits/SKILL.md) | One fixed lock order, locking before counting, re-checking after the lock, retryable busy responses, idempotency keys with prior keys, one transaction per multi-step change, and race tests with real parallel connections. |
| [internal-console-act-as-test-accounts](skills/internal-console-act-as-test-accounts/SKILL.md) | An internal console where team members act for flagged test accounts: the app's own handlers run in process, one SQL guard in every transaction, layered allow lists with refused keys and values, impersonated reads that restore claims, a console role in its own table, refusal audit rows that commit on their own, fixed config for hosted pages, and volume caps. |
| [temporary-auth-ban-lift](skills/temporary-auth-ban-lift/SKILL.md) | Letting one flagged account sign in for a bounded window while an auth ban is set: a grant row state machine under a row lock, end by the grant row, a reconciliation pass each tick, password clearing, the token residual window and an owner switch whose absent row means off. |
| [supabase-edge-functions-router](skills/supabase-edge-functions-router/SKILL.md) | One router per Edge Function with a per action allow list, identity from the token, mapped domain errors, database rate limits, the address spoofing trap, and no vendor calls from the client. |
| [supabase-storage-private-media](skills/supabase-storage-private-media/SKILL.md) | Private buckets by migration with a policy per command, owner folders, access tied to live links, minute long signed links, issue once and consume once upload paths, registration bound to the scanned version, evidence buckets, and purge order. |
| [postgres-time-zones-and-clocks](skills/postgres-time-zones-and-clocks/SKILL.md) | One clock per date rule (business zone, user zone or deliberately UTC), an audit of current_date and now()::date, server authority over device date checks, and day boundary tests with zones 25 hours apart that fail at any hour. |
| [background-jobs-and-sweeps](skills/background-jobs-and-sweeps/SKILL.md) | A scheduler that only enqueues, idempotent claims and unique constraints per stage, set based sweeps with filters before the limit, zones resolved once, isolated step budgets, reminders that stop on an ending or pause, and responders that act as users with per account on-since boundaries and daily caps. |
| [data-lifecycle-export-purge-deletion](skills/data-lifecycle-export-purge-deletion/SKILL.md) | Exports of only what a member added, hiding shared content for both at once, a download window then a bounded and logged purge, deletion that keeps the survivor's own content, held evidence, and kill switches that never block leaving. |
| [privacy-sealing-and-inference](skills/privacy-sealing-and-inference/SKILL.md) | One function decides every reveal, a guard test on every reader, checks across history, exports, realtime, push, counts, errors and timing, private skips and marks, and snapshots with minimum samples for aggregates. |

## Testing and release

| Skill | What it covers |
|---|---|
| [quality-gates-pipeline](skills/quality-gates-pipeline/SKILL.md) | The fixed gates run one at a time before a commit and in CI: typecheck, lint, Jest with its own step timeout, unused code, vocabulary, generated files, migration grants, database reset and tests, schema drift, function checks; every local gate in CI or a known gap; fresh database for trusted runs; OS crash reports before bisecting; deploys only after green, migrations before functions. |
| [pgtap-database-testing](skills/pgtap-database-testing/SKILL.md) | pgTAP tests for constraints, RLS from each role, atomic rollback at each stage, "nothing else changed" hash proofs, per test settings inside a transaction, tests that take "today" from the function's clock, loop-until-empty sweeps, and a guard test for functions that read sensitive tables. |
| [deno-edge-function-testing](skills/deno-edge-function-testing/SKILL.md) | Testing Edge Functions over real HTTP: every action and error code, identity from the session, rate limits, real parallel races, restoring settings, and refusing non local hosts for destructive tests. |
| [jest-react-native-testing](skills/jest-react-native-testing/SKILL.md) | Jest with React Native Testing Library: native mocks in one setup file, state by state screen tests, copy tests, leaked timers and query cache timers, a defaults wrapper for test clients, bisecting a hang, accessibility helpers, pinning behaviour before shared changes. |
| [android-emulator-real-user-testing](skills/android-emulator-real-user-testing/SKILL.md) | Driving a release build with adb: text dumps over screenshots, tapping by bounds, two accounts, one time codes through the admin API, crash buffer, read only database checks, first launch dialogs and repeated taps, and a pass, fail or not run checks table. |
| [independent-review-before-deploy](skills/independent-review-before-deploy/SKILL.md) | Getting a fresh review before a push that auto deploys: what to give the reviewer, briefing it on goals to break, keeping reviews on security sensitive tools, requiring failing scenarios and smallest fixes, reviewers who do not edit, and checking held changes in a separate worktree. |
| [maestro-and-flow-tests](skills/maestro-and-flow-tests/SKILL.md) | Maestro flows on seeded fixtures with stable ids, whole-string assertions, retries for late controls, tap patterns that work, hidden elements, and reporting flows that were written but not run. |
| [feature-flags-and-safe-rollout](skills/feature-flags-and-safe-rollout/SKILL.md) | Shipping features off behind a settings row with a tester audience, server side checks on every path, additive migrations, old builds keeping working, step by step device checks, a kill switch that leaves safety actions working, opening to everyone as a data change, and keeping a built feature's rules fixed when it is switched on. |

## AI features and process

| Skill | What it covers |
|---|---|
| [llm-assistant-safety-layers](skills/llm-assistant-safety-layers/SKILL.md) | Server side safety layers for an in app AI assistant: rules pre filter with fixed crisis replies (no model call), context builder, output validator, scripted fallback. |
| [llm-context-allow-list](skills/llm-context-allow-list/SKILL.md) | Enforce what a model may see, in SQL, in code and in tests; untrusted user text, private data, shared spaces, server side scope. |
| [llm-red-team-gate](skills/llm-red-team-gate/SKILL.md) | Red team case suite, judge validation, the release gate, exact reporting, outages as not run, and the cost of runs. |
| [llm-cost-and-budgets](skills/llm-cost-and-budgets/SKILL.md) | Daily caps and monthly budgets held by reservation under a lock, scripted resting replies, free fixed replies, charge on delivery, logging without content, curated designs over model calls. |
| [agent-orchestration-for-builds](skills/agent-orchestration-for-builds/SKILL.md) | One planner and reviewer with cheaper executors, complete briefs, one agent per worktree, holding paths back, long run checks and zsh pitfalls. |
| [spec-first-context-protocol](skills/spec-first-context-protocol/SKILL.md) | Spec before code, numbered decision records, session log, one open questions list, proposed values as rows, "as built" notes. |
| [honest-status-reporting](skills/honest-status-reporting/SKILL.md) | Verified, not run and inferred; gates with counts; push versus switch on; exact red team numbers; repeated-run counts for intermittent fixes; count differences checked against the working tree first; defects by severity; plain corrections. |
| [milestone-loop-build-review-test](skills/milestone-loop-build-review-test/SKILL.md) | The milestone loop from spec to documents, with what each stage caught that the previous one missed. |

Agent definitions that apply these skills are in [agents/](agents/README.md).
