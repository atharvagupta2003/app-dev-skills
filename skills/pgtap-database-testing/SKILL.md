---
name: pgtap-database-testing
description: Testing Postgres and Supabase with pgTAP. Covers constraint tests, row level security checked from each role, invariants, atomic rollback at every stage of a multi step function, "nothing else changed" proofs by hashing the rows that must stay untouched, per test settings inside a transaction, and a guard test that lists every function reading a sensitive table. Load when writing or reviewing SQL tests, RLS policies, or multi step database functions.
---

# pgTAP database testing

## When to use this
- Writing a new table, constraint, trigger, RLS policy or database function.
- Changing a function that writes to several tables in one transaction.
- Adding a function that reads sensitive data, or reviewing one.
- A test run needs to set a flag or a setting that another test also reads.

## Rules
1. **Test every table's RLS from each role.** Check the owner, another signed in user, and anon. Use `set local role` and set the JWT claims inside the same transaction.
   Why: the owner's view alone cannot show a leak. A test that runs as the owner passes whether or not the policy holds for anyone else.
2. **Test constraints by their error, not just by "it failed".** Use `throws_ok` with the SQLSTATE and the message the function raises.
   Why: a bare failure passes for any reason, including a typo in the test.
3. **Enforce rules in a trigger too, and test the trigger by bypassing the function.** An age check lived in the function and in a trigger on the table. The test updates the table directly and expects the trigger to refuse.
   Why: a function can be skipped by an admin path or a later change. The trigger is the backstop.
4. **For a function that writes several tables, prove atomic rollback at each stage.** Install a test-only trigger that raises on each table in turn, call the function, and assert that nothing changed.
   Why: a multi step change that fails half way must leave every table as it was. Testing one failure point is not enough; test each stage.
5. **Prove "nothing else changed" with a hash.** Hash every row of each table that must stay untouched, before and after the call, and compare. Leave out only the columns the function is allowed to change.
   Why: a row count or a single spot check misses a changed column. A hash over the whole row catches it.
6. **Set the settings a test needs inside that test's own transaction, and never assume the database is empty.** Use `set_config(..., true)` so the value ends with the transaction, and give every test its own ids and its own area of data.
   Why: in one project a load run's cleanup left points behind, and a worker test raced a cron job that seeded the same data. Data a test leaves behind changes what a later test counts.
7. **Keep a guard test that lists every function that reads a sensitive table.** The test compares the list with an expected list and fails when a new function appears.
   Why: a new reader can leak private data without any test failing. The guard forces a person to look at each new reader. The project's guard also had to follow functions that call other functions (a "transitive reader guard" added in review).
8. **Write tests that prove something is absent.** For example: a chat function on a thread with no participants must refuse; a helper must not exist for a role.
   Why: a missing check is a bug that a passing happy path test never shows.
9. **Run database tests only against the local stack.** Never point a test at a hosted project.
   Why: a rule that purges or deletes can destroy hosted data. A purge test that ran across the whole database would have purged every due record on a hosted project if it had been pointed at one. See the Deno skill for the same guard in code.
10. **Take "today" in a test from the function's own clock helper, never from `current_date`.** Wrap the function the app uses, for example `pg_temp.today(member)` calling the member's today function, and build every date from it.
   Why: `current_date` is the session zone (UTC in CI). A test on that clock and a function on a member's zone disagree for part of each day. See [postgres-time-zones-and-clocks](../postgres-time-zones-and-clocks/SKILL.md).
11. **Make a sweep test loop until a pass reaches nobody, with a bound.** Do not assume a fixed number of batches clears the work.
   Why: a local database keeps rows that earlier HTTP tests committed. A sweep that ran "three batches" passed on a fresh CI database and failed locally.
12. **Scope every count to the test's own fixtures.** Count only the ids the test created, not the whole table.
   Why: the same reason as rule 11. A "no such row exists" count across the table fails on any database that holds rows from earlier runs.

## How to do it

A test file runs inside one transaction and rolls back at the end:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

-- Deterministic ids for this file only.
create function pg_temp.u(tag text) returns uuid language sql immutable as
  $$ select ('aaaaaaaa-0000-0000-0000-' || lpad(substr(md5(tag), 1, 12), 12, '0'))::uuid $$;

-- Act as a signed in member for the rest of this transaction.
create function pg_temp.as(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
end $$;
```

Role checks inside the same transaction:

```sql
set local role authenticated;
select pg_temp.as(pg_temp.u('member-a'));
select is((select count(*)::int from public.items where owner_id = pg_temp.u('member-b')), 0,
  'a member cannot see another member''s items');
reset role;
```

Hash the rows that must not change (the core of the "nothing else changed" proof):

```sql
create function pg_temp.fingerprint(p uuid) returns text language plpgsql as $$
declare h text; acc text := '';
begin
  -- one hash per table; leave out only the columns the function may change
  select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.id), ''))
    into h from public.items x where x.owner_id = p;
  acc := acc || '|items:' || h;
  select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.id), ''))
    into h from public.member_profiles x where x.member_id = p;
  return md5(acc || '|profiles:' || h);
end $$;

create temp table t_before (h text);
insert into t_before select pg_temp.fingerprint(pg_temp.u('member-a'));
-- ... call the function that must fail or must touch only its own rows ...
select is(pg_temp.fingerprint(pg_temp.u('member-a')), (select h from t_before), 'member a is unchanged');
```

Atomic rollback at every stage. Install a trigger that raises on one table, then check the function failed and nothing moved:

```sql
create function public.test_fail_on() returns trigger language plpgsql as $$
begin
  if tg_table_name = any (string_to_array(current_setting('test.fail_table', true), ',')) then
    raise exception 'test_fail_on %', tg_table_name;
  end if;
  return new;
end $$;
create trigger fail_items before insert or update or delete on public.items
  for each row execute function public.test_fail_on();
-- one trigger per table the function writes; then, for each table name:
select set_config('test.fail_table', 'items', true);
select throws_ok($$select public.move_items(...)$$, null, null, 'fails at items');
select is(pg_temp.fingerprint(pg_temp.u('member-a')), (select h from t_before), 'rolled back at items');
```

Repeat for every table the function writes. The triggers, the function and the setting disappear at `rollback`.

Guard test for sensitive readers:

```sql
select results_eq(
  $$ select p.proname::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prosrc ilike '%private_answers%'
      order by 1 $$,
  $$ values ('answer_summary'::text), ('export_member_data'::text) $$,
  'only the listed functions read private answers'
);
```

The expected list is short and reviewed. A new reader makes this test fail until someone adds it on purpose.

## Gotchas
- **Symptom:** a test passes alone and fails in the full run.
  **Cause:** it relied on a row, a setting or a clock that another test or an earlier run left behind. In one project a cron job seeded data during a worker test.
  **Fix:** create the data it needs with its own ids, set settings inside its own transaction, and take dates from the function's own clock helper, never fixed dates and never `current_date` (rule 10).
- **Symptom:** a database test fails only for part of each day in CI, and passes locally.
  **Cause:** the test built dates with `current_date`, which is the session zone (UTC in CI), while the function used a business or member zone. A test that changed a member's zone also did not restore it.
  **Fix:** the helper in rule 10, a restore inside any test that changes a zone, and a day test with two zones 25 hours apart. See [postgres-time-zones-and-clocks](../postgres-time-zones-and-clocks/SKILL.md) for the full example. Also, `now()` never moves inside a test, so a harness that varies the session zone does not prove a real midnight crossing.
- **Symptom:** a "no such row exists" check or a sweep test fails on a local database and passes on a fresh CI database.
  **Cause:** HTTP level tests committed rows to the local database, and later tests counted or swept them. (Recorded once in the project, not a general rule.)
  **Fix:** rules 11 and 12, and reset the local database before a trusted full run (see [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md)).
- **Symptom:** an RLS test passes even though the policy is wrong.
  **Cause:** the test ran as the table owner or as the service role, which bypasses RLS. (General: a common cause, not one recorded in this project.)
  **Fix:** `set local role authenticated` and set the JWT claims, then check the row counts. Confirm the count is non zero for the owner so the test is not vacuous.
- **Symptom:** the hash differs even though nothing meaningful changed.
  **Cause:** a column like `updated_at`, or a value that changes on every read, is in the hash. (General.)
  **Fix:** remove exactly those columns, and say why in a comment.
- **Symptom:** a stage test passes but the function still left a partial write.
  **Cause:** the failure hook was attached to only one of the tables the function writes, so the other writes were never tested. (General.)
  **Fix:** attach the hook to each table the function touches, and assert the fingerprint after each failure.
- **Symptom:** a new function reads private data and every test still passes.
  **Cause:** no test lists the readers, so nothing notices the new one. (General.)
  **Fix:** the reader guard test in rule 7.

## Checklist
- [ ] Each table's RLS is tested for the owner, another user and anon.
- [ ] Every constraint test checks the SQLSTATE or the message.
- [ ] Every multi table function has a rollback test per stage.
- [ ] The "nothing else changed" hash covers every table the function must not touch.
- [ ] Settings are set with `set_config(..., true)` inside the test transaction.
- [ ] The test file ends with `rollback;`.
- [ ] The sensitive reader guard lists the new function, or the test fails for a reason a person must review.
- [ ] No test takes "today" from `current_date`, and each test that changes a zone restores it.
- [ ] Sweep tests loop to empty, and counts are scoped to the test's own fixtures.

## Tests that prove it
- Run `supabase test db` against a freshly reset local database, then again after an unrelated test run, and expect the same result.
- Delete one RLS policy on purpose in a scratch branch and confirm the RLS test fails.
- Add a new function that reads a sensitive table and confirm the guard test fails.
- Run the file with two members in zones 25 hours apart under several session zones, and confirm a `current_date` version of the function fails.

## Related skills
- [postgres-time-zones-and-clocks](../postgres-time-zones-and-clocks/SKILL.md): clocks, day boundary tests and the zone harness.
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md)
- [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md)
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md)
