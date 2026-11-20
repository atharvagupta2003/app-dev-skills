---
name: temporary-auth-ban-lift
description: How to let one flagged account sign in for a short, bounded window while the auth provider holds a ban, without leaving it able to sign in forever. Covers a grant row with open, closing and closed states under a row lock, undoing a lift when the grant is no longer open, ending by the grant row rather than the full guard, a reconciliation pass at the start of every tick keyed on markers on the auth user, clearing passwords set during the window, the access token window that outlives a ban, gating risky actions for these sessions, and an owner switch whose absent row means off. Load when a feature lifts or restores an auth ban, bans or unbans accounts through an auth admin API, or runs a scheduled reconciliation over accounts.
---

# Temporary auth ban lift

## When to use this
- A test or support feature must let one account sign in while the provider's ban is set.
- A feature bans or unbans accounts through an auth admin API.
- A scheduled job must repair state that a failed call may have left wrong.
- You are about to write two separate calls: one to lift the ban and one to restore it.

## Rules
1. **Model the lift as a recorded state machine, not as two calls.** A grant row moves from open to closing to closed. Why: the lift and the restore call an auth admin API outside the database transaction. A race or a partial failure between the two calls can leave an account able to sign in, with no record of why.
2. **Take every transition under a row lock on the grant.** Open the grant, lift the ban, then let the code that issues the sign in confirm under the same lock. If the grant is no longer open when the confirm runs, undo the lift. Why: a grant closed during the lift would otherwise leave the account unbanned.
3. **End the grant by its row, not by running the full guard again.** Why: if a marker on the account changes during the window, the guard refuses. An end step that re runs the guard can then never complete, and the account stays unbanned.
4. **Run a reconciliation pass first in every tick.** Re ban any marked account that can sign in and has no open grant. Key it on markers stored on the auth user itself, so it still finds the account after the app's own rows are deleted. Run it before any long step, so the long steps cannot starve it. Why: the pass repairs failures left by earlier ticks.
5. **Count what a destructive pass would select, read only, before you deploy it.** For a pass that should select nothing, the count must be zero. Why: a re ban pass that selects the wrong accounts changes real accounts.
6. **Clear any password set during the window before the restore.** Why: a password is a credential that outlives the window and can work after the ban returns. (This is reasoning from the design. No incident is recorded for it.)
7. **State the residual window in the notes and the report.** An access token issued during the window can keep working against the data API until it expires, even after the ban returns. Say so, with the token lifetime. Do not claim that the ban ends the session at once.
8. **Gate what the window session may do.** While the grant is open, the session is a normal user session. Decide which actions it must not perform, for example reports about real users and paid model calls. Refuse them for flagged accounts in the shared gate, not only in the screen.
9. **Ship the feature off behind an owner switch whose absent row means off.** Only the owner changes the row, and only through SQL. Why: if an absent row meant on, every environment that ran the migration would turn the feature on.

## How to do it

A sketch of the grant table. It has not been run against a shipped schema:

```sql
create table public.ban_grants (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id),
  state       text not null default 'open' check (state in ('open', 'closing', 'closed')),
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
-- At most one live grant per account, enforced by the database.
create unique index ban_grants_one_live
  on public.ban_grants (user_id) where state in ('open', 'closing');
```

The steps, each under the lock on the account's grant:

```text
open     insert the grant as open with an expiry. Lift the ban through the auth admin API.
confirm  the code that issues the session takes the same lock. If the grant is not open,
         re apply the ban and refuse. Otherwise issue the session.
close    set the grant to closing. Re apply the ban. Set the grant to closed.
         If the ban call fails, the grant stays closing and the next tick finishes it.
tick     first, reconcile: for each marked account with no open grant that can sign in,
         re apply the ban. Then run the other steps.
```

Whether a grant in the closing state should count as "no open grant" for the reconciliation is not settled in the material this skill was built from. Decide it, and test the race in both directions.

## Gotchas
- **Symptom:** a flagged account can sign in long after its window. **Cause:** the lift succeeded, the restore call failed, and nothing recorded that the account was open. **Fix:** write the grant before the lift, and run the reconciliation pass at the start of every tick.
- **Symptom:** the restore never completes after a marker on the account changed. **Cause:** the end step re ran the full guard, and the guard now refuses. **Fix:** end by the grant row.
- **Symptom:** an account is unbanned after its grant was closed. **Cause:** the confirm did not take the lock, so it ran after the close. **Fix:** confirm under the lock, and undo the lift when the grant is not open.
- **Symptom:** a password set during the window still works after the restore. **Cause:** the restore did not clear the password. **Fix:** clear it as part of the close.
- **Symptom:** the reconciliation never ran during a busy tick. **Cause:** a long step ran first and hit the tick's time limit. **Fix:** run the reconciliation first.
- **Symptom:** an account can still reach the data API after its ban was restored. **Cause:** a token issued during the window is valid until it expires. **Fix:** this is the residual window. Keep the token lifetime short, and state the window.

## Checklist
- [ ] The lift is a grant row with open, closing and closed states.
- [ ] Each transition runs under a row lock, and the confirm undoes a lift when the grant is not open.
- [ ] The end step uses the grant row, not the full guard.
- [ ] The reconciliation pass runs first in each tick and keys on markers on the auth user.
- [ ] The count of the reconciliation's selection was checked on real data, read only.
- [ ] Passwords set during the window are cleared at close.
- [ ] The residual token window is stated.
- [ ] Risky actions are refused for flagged sessions in the shared gate.
- [ ] The feature is off behind an owner switch, and an absent row means off.

## Tests that prove it
- Race test: run open and close in parallel, many times. The account must end banned whenever no grant is open, and the grant table must never hold two live rows.
- Failure test: make the lift call fail, then the restore call fail. The next tick must leave the account banned with no open grant.
- Confirm test: close the grant between the lift and the confirm. The confirm must refuse, and the lift must be undone.
- Marker test: change a marker during the window, then close. The close must still complete.
- Reconciliation test: create a marked account that can sign in and has no grant. One tick must ban it. A second tick must change nothing.
- Password test: set a password during the window, close, and check that sign in with it fails.
- Switch test: with the switch row absent, every lift call must refuse.

## Related skills
- [internal-console-act-as-test-accounts](../internal-console-act-as-test-accounts/SKILL.md): the console that uses these windows, and its guards.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): the tick and the reconciliation step.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md): owner switches and the kill switch rules.
- [supabase-migrations-discipline](../supabase-migrations-discipline/SKILL.md): counting a destructive selection before deploy.
- [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md): lock order and races.
