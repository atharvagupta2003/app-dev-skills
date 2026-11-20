---
name: internal-console-act-as-test-accounts
description: How to build an internal console where team members act on behalf of flagged test accounts, without creating a side door into real member data. Covers running the app's own server handlers in process under the test account's identity, one hard guard in SQL inside every transaction, two layer allow lists with refused payload keys and values, impersonated reads that restore the caller's claims, a console role in its own table with fail closed per action role lists, refusal audit rows that commit on their own, hosted console pages with fixed config, lead-with-what-is-waiting workflows, and volume caps. Load when building a support, QA or test account tool that writes as another user, or any internal tool that reads member data.
---

# Internal console that acts as test accounts

## When to use this
- Team members must reproduce or fix a problem by acting as a test account in the real app.
- An internal tool can read or write member rows, send messages or start actions for other users.
- You are adding an action to an existing allow list, or a new role to an internal tool.
- An internal page is hosted on a public address and talks to a backend.

## Rules
1. **Run the app's own server handlers, in process, with the identity set to the test account.** Do not mint sessions for test accounts, and do not copy the handler logic into the console. Why: the same handlers keep the same checks in force, so the console exercises the path the app runs. (This was the design goal. It was reviewed four times, not measured against the alternative.)
2. **Guard every read and write with one hard rule function in SQL, called inside the same transaction.** The guard requires several independent markers, all present. For example: a marker on the auth user, a row in a test account table, and an active flag. Pass the guarded id into the work itself, so the check and the work cannot name different accounts. Why: a check at the router can be skipped by a new action, and a check on one id while the work touches another is an easy gap.
3. **Allow an action only when two layers agree.** A code registry and the SQL allow rows must both allow it, and both mark it "server only". Why: one layer can drift from the other, and the database still refuses when the code does not.
4. **For every action added to an allow list, read its input schema and the SQL it reaches.** Look for optional keys or values that reach moderation, reports, other users, money, model or vendor calls, or precise location. Keep a refused key list and a refused value list for each action. Why: allowed actions hid side doors. An "unmatch" action carried an optional report object that reached moderation. A check-in action carried a value that raised a safety event.
5. **Restore every claim an impersonated read changes, on every exit.** Set the request's JWT claims to the test account for one read. Put the caller's claims back on normal return and on the exception path, and test both. Why: `set_config(..., true)` inside a function that has a SET clause did not revert when the function returned, so the claims stayed set. Keep reads as a fixed list of branches, not dynamic SQL. Leave out any read that returns precise location, even if the app uses it.
6. **Give the console role its own table.** Do not add a value to an existing role enum. Why: the existing moderation SQL authorised any row in the admin table. A tester value in that enum would have let testers into moderation at the database level.
7. **Check the console role per action in the router, and refuse every action not listed for it.** A new action is closed to the console role until someone lists it. Why: this fails closed without touching the older functions that check other roles.
8. **Grant only the lowest role from the UI.** Owner rows are created by a one time data change, never by the console. Why: a UI that can grant its own top role is an escalation path.
9. **Write refusal audit rows through a call that commits on its own.** A refusal raised inside the guarded transaction rolls back its own audit row, so attempts against real accounts left no trace. Record the actor, the attempted target, the action and the refusal code. Never record the payload.
10. **Serve a hosted console page from a fixed config file.** Never read the backend address or key from URL parameters. Allow a local override only when the page is served from localhost and points at localhost. Narrow the content security policy's connect and image sources to the configured host. Why: a static page read its backend from the link, so a crafted link could send one time codes and sessions to another host.
11. **Lead with what is waiting on the tester.** The landing screen lists only the test accounts linked to the tester's own app account: requests sent, matches and items waiting. Each row offers one-click actions. Keep the full list on a second screen. Why: testers had to search about 1,500 test accounts before the owner asked for the landing list.
12. **Make linking a console login to an app account narrow and uniform.** Restrict the possible targets, and return one refusal for every failure, including "no such account". Why: a different answer for a missing address lets anyone find out whether an address has an account.
13. **Bound the volume of every tool that creates accounts, uploads files or calls a vendor.** Use per actor daily caps stored as settings rows. Why: a review asked what stopped one tester creating unlimited accounts. The caps were missing until then.

## How to do it

A guard that every console function calls, and a write that uses the same id:

```sql
create function private.assert_console_target(p_user uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from auth.users u
    join public.test_accounts t on t.user_id = u.id
    where u.id = p_user
      and u.raw_app_meta_data ->> 'test_account' = 'true'  -- marker 1: on the auth user
      and t.is_active                                      -- marker 2: the table row is active
  ) then
    raise exception 'target_refused' using errcode = 'P0001';
  end if;
end;
$$;

create function private.console_update_bio(p_target uuid, p_bio text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_console_target(p_target);       -- same id ...
  update public.profiles set bio = p_bio
  where user_id = p_target;                              -- ... as the work
end;
$$;

revoke execute on function private.console_update_bio(uuid, text) from public, anon, authenticated;
```

The guard here has two markers. Add a third (for example, a profile flag) when the risk is high. Every marker must be present.

The router calls the guarded function, and writes the refusal audit row in a separate call. Each RPC call is its own transaction, so the audit row survives the refusal:

```ts
const { error } = await admin.rpc('console_update_bio', { p_target: target, p_bio: input.bio });
if (error) {
  await admin.rpc('log_console_refusal', {   // separate call, commits on its own
    p_actor: consoleUserId, p_target: target, p_action: 'update_bio', p_code: refusalCode(error),
  });                                         // never the payload
  return fail(403, 'refused');
}
```

Refused payload keys and values for an action sit next to its allow row. Check them before the call:

```ts
const refusedKeys = { update_bio: ['report', 'notify_user'] } as const;
const refusedValues = { update_bio: [/* values that reach moderation */] } as const;
```

## Gotchas
- **Symptom:** an allowed action sends a report or a moderation event that the action does not name. **Cause:** an optional key in the input reaches a moderation function. **Fix:** refuse that key for that action, and add a test that sends it.
- **Symptom:** a refused attempt against a real account leaves no audit row. **Cause:** the audit insert ran inside the guarded transaction, which rolled back. **Fix:** write the refusal through a separate call after the guarded call returns an error.
- **Symptom:** after one impersonated read, the caller's later reads return the test account's data. **Cause:** the claims were not restored after the function returned, or the exception path skipped the restore. **Fix:** restore on every exit, and test a read that raises.
- **Symptom:** testers can open the moderation tools. **Cause:** the console role was added to a shared enum that moderation checks with "any row". **Fix:** a separate table for the console role, and a per action role list in the router.
- **Symptom:** a shared admin link sends one time codes to a different host. **Cause:** the page reads its backend from the query string. **Fix:** a fixed config file, and a narrowed connect source in the content security policy.
- **Symptom:** a tester can tell whether an address has an account. **Cause:** the link function gave one answer for "no such account" and another for "not allowed". **Fix:** one uniform refusal for every failure.
- **Symptom:** a tool creates accounts without limit. **Cause:** no volume bound was in the first design. **Fix:** a per actor daily cap in a settings row, checked before each create.

## Checklist
- [ ] Each action runs the app's own handler, with the test account's identity.
- [ ] The guard is called in the same transaction, with the id the work uses.
- [ ] The action is on both the code registry and the SQL allow rows, each marked server only.
- [ ] Every optional key and value in the action's input has been checked for side doors, and refused ones are listed.
- [ ] Impersonated reads restore the caller's claims on every exit.
- [ ] Console access lives in its own table, and every action lists its allowed roles.
- [ ] Only the lowest role can be granted from the UI.
- [ ] Refusal rows are written through a separate call and hold no payload.
- [ ] The hosted page reads a fixed config file, and its content security policy names only that host.
- [ ] Account creation, uploads and vendor calls have daily caps in settings rows.

## Tests that prove it
- For each action, call it with each refused key and each refused value. Each call must be refused, and the refused key must not reach the moderation function.
- Call the guard with a real account, one with each marker missing, and an inactive row. Each must refuse with the same code.
- Call each action as the console role, and as a role not listed for it. Unlisted actions must refuse.
- After a refused call, check that the refusal row exists, names the target and the code, and holds no payload.
- Make an impersonated read raise an error. Check that the caller's claims are back afterwards.
- Load the hosted page with a link that carries a host parameter. The parameter must be ignored.
- Send the cap limit plus one. The last call must refuse, and the count must not include refused attempts. Pin any random delay to zero in this test, so the test cannot cross midnight.

## Related skills
- [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md): the rules for the functions the console calls.
- [supabase-edge-functions-router](../supabase-edge-functions-router/SKILL.md): the per action router and its error mapping.
- [temporary-auth-ban-lift](../temporary-auth-ban-lift/SKILL.md): the window in which a flagged account may sign in, and the gates for that session.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): responders that act as test accounts on a schedule.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md): the review that found side doors in this design.
- [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md) and [pgtap-database-testing](../pgtap-database-testing/SKILL.md): where the tests above are written.
