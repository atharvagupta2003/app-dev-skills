---
name: supabase-migrations-discipline
description: How to change a Supabase or Postgres schema safely. Covers migrations as the only route to the database, declarative schema files checked by a diff in CI, enum values in their own migration, never editing an applied migration, signature changes that old server code survives, idempotent data fixes and backfills when a rule loosens, and a script that checks function grants and search paths. Load before writing any migration or changing a function or enum.
---

# Supabase migrations discipline

## When to use this
- You are about to write a migration, add a table, column, index, function, policy, cron job, bucket or enum value.
- You are about to change the signature of a SQL function that a deployed Edge Function or app build calls.
- You are about to write a data fix inside a migration, or a one-off cleanup.
- A teammate says "I just fixed it in the dashboard". Stop and bring the change back into a migration.

## Rules
1. **Nothing exists in the database that is not in a migration.** A production database held twelve tables with no `CREATE TABLE` in the repository, a partial unique index that stopped duplicate threads, a hand-altered CHECK, a storage bucket, realtime membership and cron jobs. A reset from the repository would have produced a database that was less correct than production, silently. A silent difference is worse than an error.
2. **Keep declarative schema files and generate migrations from them.** One file per object (tables, functions, policies, triggers, enums, cron, realtime publication, buckets). Migrations are forward only, generated from those files, and never edited after merge. A reviewer then reads a function as it will exist, not as a chain of deltas.
3. **Gate every pull request with a reset and a diff.** Run a reset from clean against a preview database; any error fails. Then `db diff` must be empty. Run the same diff nightly against production and alert on a non-empty result. This is what catches a change made by hand in a dashboard.
4. **Pin the migration CLI version in CI.** An unpinned CLI can change how `db diff` prints, and then the drift gate passes when it should not.
5. **Put new enum values in their own migration, committed before any migration that uses them.** A value added and used in the same step fails or behaves unpredictably. Give the enum change its own file so its commit comes first.
6. **Never edit an applied migration.** A mistake is fixed by a new forward migration. A down migration that has run against real data is an untested second path at the worst time, so migrations here do not roll back.
7. **Change a function signature in two steps when old code is still running.** Between the migration and the function deploy, old server code calls the old signature. Add the new parameter with a default so both shapes work, deploy, then move callers, then remove the old shape later. (Hypothesis from general practice. Not yet exercised in a shipped change, so test it on a staging database first.)
8. **A data fix inside a migration is idempotent and touches only rows that are finished.** Select rows that are not in progress and are older than a threshold (for example "not in progress and older than an hour"). A cleanup that does not check for in-flight work can delete a row while a request is still writing it. (The rule is taken from the project's review notes. The specific incident is not recorded in the material this skill was built from, so treat the threshold as a starting point.)
9. **Add a column with a non-volatile default.** In current Postgres, a constant default, or a stable one such as `now()`, is recorded in the catalogue and does not rewrite the table. A volatile default such as `random()` or `clock_timestamp()` is evaluated for every existing row and rewrites the table. Check the default's volatility and your Postgres version before running it on a large table. (General Postgres behaviour, not measured in this project.)
10. **Run a grants and search path check on every migration.** Postgres gives new functions `EXECUTE` to `PUBLIC`, so every new function needs an explicit `REVOKE` from `public`, `anon` and `authenticated`, unless it is on a short allow list of functions clients are meant to call.
11. **When a migration loosens a predicate, backfill the members who already meet it, inside the same migration.** Run the existing idempotent evaluation function for exactly those members, quietly, with no notifications. Why: members who already met the looser rule did not receive the award, because the migration changed the rule but did not evaluate existing members. The backfill reuses the function the job already uses, so a second run adds nothing.

## How to do it
1. Edit the declarative file for the object, not only a migration.
2. Generate the migration from the declarative files. Name it with a timestamp and a short purpose.
3. If you added an enum value, make it its own migration and merge it first.
4. Run the reset and the diff locally. Both must pass before you write any code that uses the change.
5. Run the grants check (below) before merging.

A grants check in CI can be a short shell script. It reads each migration, finds each `create function public.<name>`, and fails unless a `revoke ... on function public.<name>` names `public`, `anon` and `authenticated`. Keep the allow list in a plain text file in the repository, one name per line, each with a comment saying why the function is client callable.

To check search paths, query the catalogue after reset. This is a sketch that has not been run against a shipped schema:

```sql
select p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and not ('search_path=""' = any (coalesce(p.proconfig, '{}')));
```

Any row returned is a function without a fixed empty search path. Decide for each one whether it is `security definer` (it must have one) or whether a fixed search path is still needed.

## Gotchas
- **Symptom:** a clean reset works locally but production has tables, indexes or policies you cannot find in the repository. **Cause:** someone applied SQL in a dashboard or as a one-off. **Fix:** capture the object in a declarative file, generate the migration, and let the nightly diff alert on the next drift.
- **Symptom:** a migration fails on a clean database but works on the one you wrote it against. **Cause:** it depends on an object that was only ever created by hand. **Fix:** the reset gate catches this; never work around it by hand-creating the object.
- **Symptom:** an enum value "exists" but a function using it errors. **Cause:** the new value and its use were in one step. **Fix:** split the enum change into its own earlier migration.
- **Symptom:** after a deploy, an old app build or an old Edge Function errors on a function call. **Cause:** the signature changed before the callers did. **Fix:** the two-step change in rule 7.
- **Symptom:** a constraint check silently allows a value the code no longer handles. **Cause:** a CHECK list was edited by hand, so the repository and production disagree. **Fix:** the diff gate, and no hand-edited CHECKs.
- **Symptom:** members who qualify under a looser rule do not have the award after the migration. **Cause:** the migration changed the predicate and did not evaluate the members who already qualified. **Fix:** a backfill inside the same migration, for exactly those members, using the existing idempotent evaluation function (rule 11). Test the backfill path: remove the award for one qualifying member, call the same function, and check the award is back, once.
- **Symptom:** a schema reset takes minutes on a large table. **Cause:** a volatile default forced a rewrite. **Fix:** a constant default, or add the column nullable, backfill in batches, then set the default.

## Checklist
- [ ] The change is in a declarative file and a generated migration.
- [ ] Enum values are in their own earlier migration.
- [ ] No applied migration was edited.
- [ ] A signature change is two steps, with a default for the old callers.
- [ ] Any data fix is idempotent and skips rows that are in progress or too recent.
- [ ] A loosened predicate has a backfill for members who already qualify, and a test of that backfill path.
- [ ] Every new `public` function revokes execute from `public`, `anon` and `authenticated`, or is on the allow list.
- [ ] Reset passes from clean and `db diff` is empty.
- [ ] The CLI version is pinned in CI.

## Tests that prove it
- A reset-from-clean job in CI on every pull request.
- A diff job that fails on any output, run on every pull request and nightly against production.
- A grants test (the script above) in CI.
- A pgTAP assertion (see [pgtap-database-testing](../pgtap-database-testing/SKILL.md)) that a deliberately absent object stays absent, for example that a table with no member access really has no member policy.

## Related skills
- [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md): what each new function and table must lock down.
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md): how the database tests are written.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md): review of migrations before they reach production.
