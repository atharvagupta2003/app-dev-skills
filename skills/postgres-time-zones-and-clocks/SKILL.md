---
name: postgres-time-zones-and-clocks
description: Getting "today" right in Postgres, Supabase and the app that calls them. Covers choosing one clock per rule (business zone, user zone or deliberately UTC), auditing current_date and now()::date, keeping the client's date check in line with the server, and tests that fail at any hour of the day. Load when a rule depends on a date or a day boundary, when a test fails only at some hours, or when a CHECK constraint or birthday rule involves the date.
---

# Postgres time zones and clocks

## When to use this
- A rule depends on "today", a day boundary, an age or a birthday.
- A database test passes locally and fails in CI, or fails only at some hours.
- You are reviewing `current_date`, `now()::date` or `date_trunc('day', now())`.
- The app checks a date rule on the device and the server checks it too.

## Rules
1. **Pick one clock per rule, and write it down.** Each rule is one of three classes: business zone (one agreed zone for everyone, used for shared boundaries), user zone (the member's own zone), or deliberately UTC (a rule enforced by a CHECK constraint). Why: two checks of one rule on two clocks agree only while sessions run in UTC.
2. **Use UTC for a rule that a CHECK constraint enforces.** Why: a constraint's meaning must not change with session settings, and a session zone is a setting any connection can change.
3. **Never use the session's `current_date` or `now()::date` for a business rule.** The session zone is whatever the connection sets. In CI it was UTC, so the wrong clock only showed at some hours. Why: the failures in one project came and went with the hour.
4. **Put each clock expression in one place, and call it everywhere.** Use one function per class, or one written expression such as `(now() at time zone 'UTC')::date`, and reuse it. Why: a copy typed into each check drifts, and the drift is found only near midnight.
5. **Audit every clock expression before you trust the rules.** Search for `current_date`, `now()::date`, `date_trunc('day', now())` and `localtimestamp`. Classify each hit as business zone, user zone or deliberately UTC. Why: the audit found an age rule on the session date and the same rule on the UTC day.
6. **Decide which side is authoritative for each date rule.** Write it down. The database is the authority for any rule it enforces. The device's own date check can only be a hint. Why: the device's local date and the server's date disagreed near a birthday. (Recommended default, not yet proven in a project. The log does not record which side one project chose.)
7. **When the server refuses, show the server's message, not the device's verdict.** Why: a device that says "allowed" and a server that says "refused" leave the member with two answers.
8. **Get "today" in a test from the same helper the function uses, never from `current_date`.** Why: a test that builds its date on the session clock and a function that builds it on the member's zone are two clocks. The test then fails for part of each day.
9. **Restore any zone a test changes, inside the test.** A member zone changed in the middle of a test and not put back moves a daily row to another day for the rest of that test. Why: a daily row landed on a different day after a zone change that was never restored.
10. **Prove a day rule with two zones about 25 hours apart.** Why: a single zone, or two zones close together, agree at some hours. At every hour, zones 25 hours apart give dates that differ, so a wrong clock fails at least one member at any hour of the day.

## How to do it

Clock classes, written once. Names here are invented:

```sql
-- Business zone: one agreed zone for shared boundaries.
create function public.period_today() returns date language sql stable as
  $$ select (now() at time zone 'Pacific/Auckland')::date $$;

-- User zone: the member's own zone, with the agreed default when none is set.
create function public.member_today(p_member uuid) returns date language sql stable as $$
  select (now() at time zone coalesce(m.time_zone, 'Pacific/Auckland'))::date
  from public.members m where m.id = p_member
$$;

-- Deliberately UTC: does not depend on the session zone.
create function public.utc_today() returns date language sql stable as
  $$ select (now() at time zone 'UTC')::date $$;
```

These are a sketch of the three classes, not tested definitions. The functions are `stable` because `now()` is stable. Whether a CHECK constraint may call a function like this is not checked in this skill; test it in your own Postgres version before you rely on it.

The day boundary test uses two zones 25 hours apart. See `examples/day-boundary.test.sql` in this skill for the full file. The key lines:

```sql
-- Two members: UTC+14 and UTC-11. Their local dates differ at every instant.
select isnt(pg_temp.today(pg_temp.u('east')), pg_temp.today(pg_temp.u('west')),
  'zones 25 hours apart give different dates');

-- Then the same check under several session zones. Only the session setting changes.
select set_config('timezone', 'America/Los_Angeles', true);
```

Run every database test file a second time with the session zone set to a non UTC zone (for example with `PGTZ`), and with the business zone overridden inside the test's own rolled back transaction. A test that breaks only under the second run was reading a session clock.

## Gotchas
- **Symptom:** a database test fails in CI only in some hours of the day, and passes locally.
  **Cause:** the test built its date with `current_date`, which is the session zone (UTC in CI). The function used a business or member zone, so the two agreed only for part of each day.
  **Fix:** take "today" from the function's own helper (rule 8). Run the day test with two zones 25 hours apart.
- **Symptom:** a daily row lands on the wrong day in one test, and the next test in the same file fails.
  **Cause:** an earlier test changed a member's zone and did not restore it.
  **Fix:** restore the zone inside the test that changed it (rule 9).
- **Symptom:** a test with two members passes at most hours.
  **Cause:** both members' zones are close together, so their dates match at most hours.
  **Fix:** use zones about 25 hours apart (rule 10).
- **Symptom:** a member is refused by the app and accepted by the server, or the reverse, near midnight or a birthday.
  **Cause:** the device checks its local date, and the server checks its own date in another zone.
  **Fix:** make the server authoritative and show its message on refusal (rules 6 and 7).
- **Symptom:** a clock rule works in development and differs in production.
  **Cause:** the two environments use different session zones, and the rule read `current_date`.
  **Fix:** the audit in rule 5, then one class per rule.
- **What the day test does not prove.** `now()` is fixed inside a transaction and did not move in any of these runs. The tests prove that each zone expression picks the right day at the current instant, and they make a wrong clock fail at any hour. They do not run the function across a real midnight. A possible next step, not tried in the project: pass the instant into the function as a parameter, so a test can move it. Hypothesis, unverified.

## Checklist
- [ ] Every date rule is classed as business zone, user zone or deliberately UTC.
- [ ] No business rule reads `current_date` or `now()::date`.
- [ ] Each clock expression is defined once, and every check calls it.
- [ ] A CHECK constraint that uses a date uses the UTC class.
- [ ] The authoritative side of each client and server date check is written down.
- [ ] A refused date rule shows the server's message on the device.
- [ ] Tests take "today" from the function's helper.
- [ ] Any zone a test changes is restored inside that test.
- [ ] A day boundary test uses zones about 25 hours apart.
- [ ] The database tests pass with a non UTC session zone as well as with UTC.

## Tests that prove it
- The day boundary test in `examples/day-boundary.test.sql`, run under several session zones.
- Replace one clock expression with `current_date` on purpose in a scratch branch, and confirm the day test fails at every hour.
- A client test for a birthday or a day edge: the device message matches the server's refusal.

## Related skills
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md): the test file layout, transactions and settings.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): zones for reminders, and resolving each zone once.
- [offline-outbox-and-sync](../offline-outbox-and-sync/SKILL.md): a daily cap's reset time comes from the server.
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md): run the database tests in CI as well as locally.
