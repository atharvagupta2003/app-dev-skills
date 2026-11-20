---
name: feature-flags-and-safe-rollout
description: Shipping a large feature to a live Expo and Supabase app safely. Covers building every new feature switched off behind one settings row with a tester audience, additive migrations, keeping old app builds working, deploying in steps with a device test at each step, testing the kill switch, and turning the feature on for everyone as a data change rather than a deploy, and keeping the rules of a built feature fixed when it is switched on. Load when planning a feature that testers or users will see, when writing a migration for a live database, or when designing a settings row.
---

# Feature flags and safe rollout

## When to use this
- A feature is large enough to ship in several milestones.
- The feature changes a path that existing users already use.
- Testers have the app and must not see unfinished screens.
- You need a way to stop the feature quickly without a new build.

## Rules
1. **Ship every new feature switched off.** Use one settings row with `enabled` false by default, and no entry point, action or card works until the row is changed.
   Why: the project's plan made the feature off by default, so a deploy that reached testers changed nothing for them until someone turned it on.
2. **Gate every read and write path on the switch, on the server.** The check must live in the database or the function, not only in the app. Include pushes, storage rules and background jobs.
   Why: an old app build can call any action. The app's hidden card does not stop a call. The project's design was reviewed and changed to check the switch on every read, write, push and storage rule for a shared space.
3. **Let a tester list choose who sees the feature while the audience is "testers".** Write the list with SQL and a privileged role only, never from the app.
   Why: a list the app can write is a list any user can add themselves to.
4. **Keep migrations additive while anything is live.** Add tables, columns with defaults, and new functions. Do not rename or remove a column that an old build reads.
   Why: old builds keep running after the deploy, so they must still find what they read. In the project, every existing member stayed in their current mode by default, and the change to an existing hot path was proved by the existing test suites still passing unchanged.
5. **Give new function parameters defaults, and add fields to responses without removing any.** An old app sends the old parameters and reads the old fields.
   Why: this is what lets the functions deploy before every app build has updated. (Derived from the additive rule above, not separately tested in the project.)
6. **Deploy in steps, and run a device test at each step.** Each milestone gets its own build, its own database changes, and its own device check before the next one starts.
   Why: a failure in step three then points at step three. One large feature in the project shipped in eight milestones, each with a new build.
7. **Test the kill switch on purpose.** With the switch off, every read, write and background step for the feature must refuse or pause, and every safety action must still work.
   Why: a kill switch is only useful if it stops the harm and leaves people able to get out. In the project, leave, block, report, export and account deletion were deliberately left working when the switch was off.
8. **Turn the feature on for everyone as a data change, after the consent build has reached testers.** Do not turn it on by deploying a new function.
   Why: a data change can be undone in one statement. A deploy cannot.
9. **When you turn on a feature that is already built, say in the brief whether its rules may change.** If an executor finds that a rule must change, it stops and reports both options to the owner. Do not choose one.
   Why: a brief asked for a built but disabled time-based award to be switched on, and said to count from a shared start date. The executor changed the award's basis from the account link date to a self declared date. Both are defensible. The self declared date can be gamed, and the link date is harder to test on a short timeline. That made it a product decision, not a code detail.

## How to do it

The settings row and the tester list, kept in the database:

```sql
create table public.feature_settings (
  id              int primary key default 1 check (id = 1),  -- one row only
  enabled         boolean not null default false,            -- off until switched on
  new_entries_enabled boolean not null default false,        -- stop new use, keep existing use
  audience        text not null default 'testers' check (audience in ('testers', 'everyone')),
  updated_at      timestamptz not null default now()
);
insert into public.feature_settings (id) values (1) on conflict do nothing;

create table public.feature_testers (
  member_id uuid primary key references public.members (id) on delete cascade
);
alter table public.feature_testers enable row level security;
-- no policies for anon or authenticated: only the service role and SQL writers can read or write it
```

The server check, used by every action of the feature:

```sql
create function public.feature_available(p_member uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.feature_settings s
    where s.id = 1 and s.enabled
      and (s.audience = 'everyone'
           or exists (select 1 from public.feature_testers t where t.member_id = p_member))
  );
$$;
```

An action checks it first and answers with a clear code:

```ts
const { data: ok } = await admin.rpc('feature_available', { p_member: caller.id });
if (!ok) return json({ error: 'feature_unavailable' }, 404);
```

Opening the feature to everyone, as a data change, after the consent build has reached testers:

```sql
update public.feature_settings set enabled = true, new_entries_enabled = true, audience = 'everyone';
```

Stopping new use only, and stopping everything:

```sql
update public.feature_settings set new_entries_enabled = false;   -- existing use keeps working
update public.feature_settings set enabled = false;               -- every read and write pauses
```

A milestone checklist that repeats for each step:

1. Migration is additive, reviewed, and proved by the existing suites still passing.
2. The new build is installed on a test device, and the feature is on for testers only.
3. The device check for this step is run and recorded (see the Android skill).
4. Only then does the next milestone's migration go out.

## Gotchas
- **Symptom:** a build that still sends the previous consent version is refused after the consent text changed. (Seen in one project's device testing.)
  **Cause:** the consent version was bumped in the app, and an installed older build still sends the version it showed.
  **Fix:** the server records the version that an older build showed, and refuses only versions it has never shown.
- **Symptom:** the switch was turned off, but people could still reach the feature through a push or a stored link. (General.)
  **Cause:** the check was in the main read function and not in the push sender or the storage rule.
  **Fix:** add the check to every path that reads the feature's data, including background jobs and storage policies, and test each one with the switch off.
- **Symptom:** a planned design said the switch only hides new entry, but a later decision made it pause everything.
  **Cause:** the first design note was not updated when the later decision was taken.
  **Fix:** read the latest decision record before coding, and update the plan when a decision changes.
- **Symptom:** a feature was switched on, and a rule the owner had set was different afterwards. (From one project's brief.)
  **Cause:** the brief said what the rule was for, not whether it could change, so the executor chose a different basis for the rule.
  **Fix:** put a line in the brief, "rule change allowed: no", and have the executor stop and report both options when a rule would need to change. The notes do not record which option the owner chose.
- **Symptom:** a deploy broke an old build because a column it read was renamed. (General.)
  **Cause:** a migration renamed or removed a column in place.
  **Fix:** add the new column, copy the data, keep the old column until no build reads it, and remove it in a later migration.

## Checklist
- [ ] The feature is off by default, with one settings row.
- [ ] Every action, push, job and storage rule for the feature checks the switch on the server.
- [ ] The tester list is written only by SQL, and the app cannot write it.
- [ ] Every migration is additive, and no old build reads a removed or renamed field.
- [ ] New parameters have defaults, and responses only gain fields.
- [ ] Each milestone has its own build, its own device check, and its own record.
- [ ] The kill switch was tested with the switch off: harm stops, and leave, block, report, export and deletion still work.
- [ ] Turning the feature on for everyone is a data change, and the consent build has reached testers first.
- [ ] When turning on a built feature, the brief says whether its rules may change, and any rule change is an owner decision.

## Tests that prove it
- With the switch off, call each action as a tester and as a non tester. Every call refuses with the same code.
- With the switch off, run each safety action (leave, block, report, export, delete). Every one must still succeed.
- Run the existing suites for the changed hot path with no edits. They must pass unchanged.

## Related skills
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md) for the kill switch and the tester list rules.
- [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md) for the HTTP refusal tests.
- [android-emulator-real-user-testing](../android-emulator-real-user-testing/SKILL.md) for the device check at each step.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md) for the review that comes before a tester sees a step.
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md) for the order of migrations and function deploys.
