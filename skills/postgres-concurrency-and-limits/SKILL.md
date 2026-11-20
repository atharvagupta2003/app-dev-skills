---
name: postgres-concurrency-and-limits
description: How to keep Postgres writes correct under parallel requests. Covers one fixed lock order (advisory locks, then rows by id), locking before counting so limits are exact, re-checking after the lock, a retryable busy response instead of a 500, idempotency keys that never let an old retry overwrite a newer edit, one transaction that builds the replacement before removing the old state, deferred constraint triggers, partial unique indexes, and race tests with real parallel connections. Load when writing any function that charges, creates, moves or limits something.
---

# Postgres concurrency and limits

## When to use this
- A function charges, spends, creates, moves, swaps, replaces or counts something a limit applies to.
- Two requests from one user, or two users acting on each other, can touch the same rows.
- You are adding a background worker that writes the same rows as a user action.
- A test passes on a single connection and you are not sure it proves anything about races.

## Rules
1. **Take locks in one fixed order everywhere.** Advisory locks first, then row locks, and within a group by id in ascending uuid order. Two functions that lock the same pair in opposite orders can deadlock. A fixed order means no cycle exists. Every multi-row function in one codebase follows the same sequence, and the order is written in a comment at the top of the function.
2. **Lock before you count.** A limit ("at most 5 open requests", "at most 3 uses a week") is only exact if the count and the insert happen under the same lock. Counting first and inserting later lets two parallel requests both see 4 and both insert.
3. **Re-check every condition after taking the lock.** The state you read before the lock may have changed. Put all refusals first, under the lock, and raise the domain error before anything is written.
4. **Turn a lock conflict into a retryable busy response, never a 500.** A deadlock or a lock timeout means "try again". Answer `409 busy_retry`, and have the client resend the same request with the same idempotency key. A 500 gives the client nothing to act on, so it cannot tell a retryable conflict from a bug.
5. **Give every charge or create an idempotency key, and store it with the result.** A replay with the same key returns the original result. A key reused for a different request is refused. Namespace keys by purpose (for example `store:<id>` or `weekly:<period>`), so a key from one feature cannot collide with another.
6. **Keep the earlier keys, so a late replay cannot overwrite a newer edit.** If a member edits an answer after a retry was queued, the old retry must not write its old value over the edit. Store the list of prior keys on the row and treat a key in that list as "already applied, return the current row".
7. **Put a multi-step change in one transaction, and build the replacement before you destroy the old state.** Compute what the new state will be, check that it is complete, then remove the old state and insert the new in the same transaction. If the replacement is not complete, raise and change nothing. A worker that deleted rows before finding replacements left users with nothing.
8. **Use deferred constraint triggers for invariants that span tables.** "A slot may hold only a live item its member is in" cannot be a CHECK. Check it at commit, so a multi-row change can pass through a temporarily inconsistent state inside the transaction.
9. **Use a partial unique index for "one live X per member".** For example, one pending request per unordered pair, or one live space per member. The index is the final guard even when the code path is wrong.
10. **Test races with real parallel connections.** A single session that runs one call after another proves only the sequence. Run two or more connections that start together and assert the end state.

## How to do it
A function that spends from a balance takes the row lock, then makes one conditional write:

```sql
create function public.spend_credits(p_member uuid, p_amount int, p_key text)
returns public.ledger_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.ledger_entries;
begin
  -- Lock the member row first, so two calls with the same key cannot both pass the replay check.
  perform 1 from public.members where id = p_member for no key update;

  -- Replay: the same key returns the original row.
  select * into v_row from public.ledger_entries
   where member_id = p_member and idempotency_key = p_key;
  if found then return v_row; end if;

  -- The balance is read under the lock, and the write is conditional on it.
  insert into public.ledger_entries (member_id, amount, idempotency_key)
  select p_member, -p_amount, p_key
   where (select coalesce(sum(amount), 0) from public.ledger_entries
           where member_id = p_member) >= p_amount
  returning * into v_row;

  if v_row is null then raise exception 'insufficient_balance'; end if;
  return v_row;
end;
$$;
```

For a function that touches two members, take both member locks in uuid order, then the request or thread row, then do the work. Write the order in the comment.

Make the Edge Function map the lock conflict to `409 busy_retry` (see [supabase-edge-functions-router](../supabase-edge-functions-router/SKILL.md)). Background workers use `for update skip locked` or try-lock so they skip what a user action holds, instead of waiting.

## Gotchas
- **Symptom:** two requests both succeed and the limit is exceeded by one. **Cause:** the count ran before the lock. **Fix:** take the lock, then count, then insert, all in one function.
- **Symptom:** an occasional deadlock error under load. **Cause:** two functions lock the same two rows in opposite orders. **Fix:** one global order, uuid ascending, and a comment at the top of each function naming it. Respond with `busy_retry`.
- **Symptom:** a user's items vanished after a "refresh" or "swap" that failed partway. **Cause:** old rows were deleted before the replacement was known, and nothing ran in a transaction. **Fix:** compute, check, then change, all in one transaction that raises on any shortfall.
- **Symptom:** a late retry from an old, slow request overwrote an edit the user made afterwards. **Cause:** the write used only the new key and accepted any value. **Fix:** prior keys stored on the row; a replayed prior key returns the current row unchanged.
- **Symptom:** a worker and a user action both create the same thing. **Cause:** the worker did not check the lock or the existing row. **Fix:** the worker tries the lock and skips on conflict; the partial unique index is the backstop.
- **Symptom:** a race test passes every time. **Cause:** it ran calls one after another on one connection. **Fix:** start two connections together, release them at the same moment, and assert on the final state.

## Checklist
- [ ] The lock order is written in a comment and matches every other function that locks the same rows.
- [ ] Each limit is checked under a lock, after the lock, in the same transaction as the write.
- [ ] Every refusal is raised before anything is written.
- [ ] Lock conflicts map to `409 busy_retry`, and the client retries with the same key.
- [ ] Every charge or create takes an idempotency key that is stored with the result.
- [ ] Edits keep their prior keys so an old replay cannot overwrite them.
- [ ] Multi-step changes build the replacement first and run in one transaction.
- [ ] Cross-table invariants are deferred constraint triggers. One-live-item rules are partial unique indexes.
- [ ] A race test runs parallel connections.

## Tests that prove it
- A parallel race test: two or more connections call the same function at once, and the test asserts the limit holds and the state is consistent. Run it against a local database.
- A replay test: the same key twice returns the same row and writes once. A reused key for a different request is refused.
- A failure test: when the replacement is short, the old state is still there.
- A deadlock test: two functions that share rows run in opposite orders under load, and the caller gets `busy_retry`, never a 500.
- The database side is written in pgTAP (see [pgtap-database-testing](../pgtap-database-testing/SKILL.md)). Parallel connections need a runner that opens real sessions, such as a Deno or Node test that uses separate clients.

## Related skills
- [supabase-migrations-discipline](../supabase-migrations-discipline/SKILL.md): where the constraint triggers and indexes are declared.
- [supabase-edge-functions-router](../supabase-edge-functions-router/SKILL.md): how `busy_retry` is returned and how the client retries.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): workers that must not collide with user actions.
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md) and [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md): where the race tests live.
