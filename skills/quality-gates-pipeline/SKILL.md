---
name: quality-gates-pipeline
description: The fixed set of quality gates for an Expo and Supabase app, run one at a time before any commit, and mirrored in CI. Covers typecheck, lint, Jest, unused code, vocabulary, generated files, migration grants, database reset and tests, schema drift, Edge Function tests, a timeout on each long step, and the rule that deploys follow a green run. Load before committing, when a gate fails, or when setting up CI.
---

# Quality gates pipeline

## When to use this
- Before any commit, to decide whether the work is done.
- When a gate fails and you are tempted to rerun it, skip it, or force past it.
- When setting up CI, or changing the deploy workflow.
- When a change touches the database, copy, prompts, generated files or Edge Functions.

## Rules
1. **Run the gates one at a time, in a fixed order, and read each result.** Do not chain them with `&&` and trust the last line. A chain hides which gate failed and whether it ran at all.
   Why: a chained run stops at the first failure, so later gates never report. Running them one by one shows exactly what passed.
2. **Run the same gates in CI as on your machine.** CI should call the same scripts and npm scripts, not a copy of their commands.
   Why: a gate that only runs locally drifts, and nobody notices until a deploy breaks.
3. **Report a failure with its output.** Paste the failing lines, the exit code and the gate name. Never write "all green" for a run you did not finish.
   Why: the project rule is to report failures honestly. A summary without output cannot be checked.
4. **Never use a force exit to get a test run to finish.** Find the open handle instead (see the Jest skill).
   Why: a "Jest did not exit" warning was not root caused for a while. The real causes were a query client's garbage collection timers left by tests and a push helper's timer that was never cleared. CI runs without `--forceExit`, so both had to be fixed.
5. **A first run after a hot reload can fail for reasons that are not in the code. Rerun once from a clean start.** If it fails again, treat it as real.
   Why: the first function test run right after the local function server reloaded failed once and passed on rerun, several times. The notes also record one transient CI failure (a package download) that passed on rerun. Do not rerun a real failure until it passes.
6. **Deploy only after a green run, and only from the tip of the main branch.** A deploy job checks the commit is still the tip before it runs, and skips if a newer commit has landed.
   Why: an older commit deployed after a newer one would put the database back to an older state.
7. **Apply migrations before deploying functions.** The deploy workflow pushes migrations, then deploys Edge Functions, then pushes auth config.
   Why: functions can then rely on new columns and tables. Keep migrations additive so an old function still works while they are applied.
8. **Refuse to deploy when a required value is missing.** A check step fails the deploy if a required secret is empty, and runs before anything is pushed.
   Why: pushing the committed local defaults would have switched off email and Google sign in on the hosted project.
9. **A suite that is a gate on your machine must be a gate in CI, or be listed as a known gap in the same change.** Do not leave it as a local-only check with no record.
   Why: the function tests ran only locally. A day boundary failure in one HTTP level test was seen only on a developer machine, because CI type checked the functions and did not run their tests.
10. **Reset the local database before a trusted full run.** Run `supabase db reset` first, then the database and function tests.
   Why: function tests over real HTTP commit rows. A later run on that database can fail or pass for a reason a fresh database does not have, so a trusted result needs a fresh start.
11. **Read the OS crash reports before you bisect your own code when a test crashes outright.** A segfault can come from the runtime.
   Why: one run segfaulted in a trivial test. The machine's crash reports pointed at memory clean up in the JavaScript runtime version in use, not at the project's code.
12. **Give every long gate step its own timeout, a little above its normal duration.** Set `timeout-minutes` on the step, not only on the job. Do not add a force exit to pass the step.
   Why: a leaked handle kept the unit test step running until the job's timeout, so the later gates never ran and nothing named the step. A step timeout fails fast, names the step, and leaves the later gates to report. A force exit would hide the leak.

## How to do it

The order that worked in this project. Run each command, read its output, then move on.

Frontend and shared code:
1. `npx tsc --noEmit` (typecheck, strict mode)
2. `npx eslint .` (lint)
3. `npx jest --ci` (unit tests; the run must exit by itself)
4. Generated files are current: a generator with a `--check` mode, for example question banks or vector fixtures. The check fails if the generated file is stale.
5. Synced copies are current: a shared domain package copied into the Edge Functions must match its source. Run the sync script in check mode.
6. Vocabulary gate: a script greps app, domain and function source for banned words (for example an ad word, a banned adjective, or a percent style score). Test files are skipped, and a line that defines a ban list carries an explicit allow marker.
7. Unused code: `knip` or a similar tool. Keep config per workspace.

Backend:
8. Migration grants: every function created in the public schema needs a revoke from public, anon and authenticated, unless it is on a named allowlist. Postgres makes new functions callable by public by default.
9. Start the local stack with only the services you need.
10. Reset the database from the migrations: `supabase db reset`. Any error fails the gate.
11. Database tests: `supabase test db` (see the pgTAP skill).
12. Schema drift: `supabase db diff` must report no changes after the reset. Run the same diff nightly against production if you can.
13. Edge Function tests: `deno test` against the local stack (see the Deno skill). Known gap: in the project this list comes from, CI type checks the Edge Functions but does not run their test suite, which runs only locally. Add the test step to CI if you copy this list.
14. Edge Function type check: `deno check` on every function entry point.

Deploy (separate workflow, only after CI passes on main):
15. Check required values are present, then check that the function secrets exist on the hosted project. Print variable names, never values.
16. Link the project, push migrations, deploy functions, push auth config.
17. Remove any temporary env file in an `if: always()` step.

## Gotchas
- **Symptom:** the unit test step hangs in CI until the job's timeout, passes locally, and the later gates never run.
  **Cause:** a timer left alive by a test. A query client's garbage collection timer can outlive a clear when a fetch was in flight, and the CI runner runs Jest in band, so one long timer keeps the whole run alive. Locally, workers are killed at the end and hide it.
  **Fix:** wrap the test client defaults and clean up after each test (see the Jest and React Query skills), and add `timeout-minutes` to the step (rule 12) so a future leak fails at once and names the step.
- **Symptom:** a schema drift check fails on a clean tree.
  **Cause:** a migration was edited after it was applied, or a schema change was made by hand in the dashboard.
  **Fix:** make a new forward migration. Editing in place is only safe before anything has been deployed.
- **Symptom:** the auth provider setting turns itself off after a deploy.
  **Cause:** the config push sent local defaults because the deploy values were empty.
  **Fix:** the required-values check must run first and must fail on empty values.
- **Symptom:** a deploy runs for an older commit after a newer one is merged.
  **Cause:** two runs queued, and the older run was not checked against the tip.
  **Fix:** compare the commit with the tip before each deploy step, and never cancel a deploy in progress.
- **Symptom:** a test run segfaults in a test that does almost nothing.
  **Cause:** a crash in the JavaScript runtime, not in the project. The machine's crash reports named the runtime version's memory clean up. (Recorded once in the project.)
  **Fix:** read the OS crash reports (rule 11) before you change project code. The project's own change to the runtime is not recorded here. Check the runtime version named in the report, and rerun from a clean start.
- **Symptom:** the CI run passes but a database or function test fails on a developer machine.
  **Cause:** the suite is not a CI gate, so CI never ran it. (Recorded once in the project.)
  **Fix:** add the suite to CI, or list it as a known gap until it is added (rule 9).
- **Symptom:** a banned word reaches users through a prompt or a string built at runtime.
  **Cause:** the vocabulary check only scans files, not generated text.
  **Fix:** keep the banned words in one list, test the copy and prompt builders with unit tests, and treat the grep as a second line of defence.

## Checklist
- [ ] Each gate ran alone, and its exit code and output were read.
- [ ] The failing gate, if any, is reported with its output.
- [ ] No gate was skipped, and no force exit was used.
- [ ] Any test file left behind a timer is fixed, not hidden.
- [ ] Each long step, including the unit test step, has its own `timeout-minutes`.
- [ ] New database functions have their revokes, or are on the allowlist with a reason.
- [ ] Migrations are new files, not edits to applied ones, and are additive.
- [ ] The deploy workflow still has the tip check, the required-values check and the order: migrations, functions, auth config.
- [ ] Every suite that gates locally is either in CI or on the known gap list.
- [ ] A trusted full database run starts from a reset database.

## Tests that prove it
- Break one gate on purpose in a throwaway branch (for example add a banned word, or a function without a revoke) and confirm CI fails on that gate and only that gate.
- Remove a required deploy value in a dry run and confirm the deploy stops before pushing anything.
- Run the Jest suite under a timeout with each file alone. Every file must exit on its own.
- In a throwaway branch, add a timer that never clears, and confirm the unit test step fails at its own timeout, not at the job's.

## Related skills
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md)
- [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md)
- [jest-react-native-testing](../jest-react-native-testing/SKILL.md)
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md)
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md)
