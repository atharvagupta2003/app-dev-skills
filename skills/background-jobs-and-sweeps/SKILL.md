---
name: background-jobs-and-sweeps
description: How to run scheduled work in Supabase without duplicates, starvation, time-zone mistakes or cross-feature failures. Covers a scheduler that only enqueues while a worker does the work, idempotent claims, set-based sweep steps with filters before the batch limit, resolving time zones once per zone, isolated step budgets, deadlines as columns, and suppressing reminders after an ending, a freeze or a long pause. Load when adding a cron job, a queue, a worker step, a reminder or any time-based behaviour.
---

# Background jobs and sweeps

## When to use this
- You are adding a `pg_cron` job, a queue, a worker step, a sweep or a scheduled push.
- A feature needs something to happen at a time, after a deadline, or on a day boundary.
- Reminders, expiries or nudges must stop when something ends or is paused.
- A job is slow, runs twice, skips people, or stops other features when one part fails.

## Rules
1. **The scheduler only enqueues. A worker does the work.** `pg_cron` runs plain SQL that inserts due work into a queue. It never calls a function, makes an HTTP call or loops over rows. A cron job that looped over users in one call had no cursor, no resume and no record of progress. Its read was also silently truncated at about two hundred active users, so the job acted on a partial list.
2. **Claim each piece of work idempotently.** Before acting, insert a claim row keyed on the job, the member and the period with `on conflict do nothing`, in the same transaction as the act. No row returned means it was already done. Duplicates, retries and overlapping workers then change only latency.
3. **Make each sweep step one set-based statement, and apply every filter before the batch limit.** A filter that removes "already done" rows must run before `limit`. If the limit comes first, the first batch fills with finished rows and everyone after it never gets a turn.
4. **Resolve a catalogue lookup once per distinct value, never once per row.** Why: a reminder sweep took 24.4 seconds for 450 rows with nothing due, because an existence check against the time zone catalogue view ran once per row. Resolving each distinct zone once brought it to about 22 ms for 495 rows. Resolve each distinct zone once, in a small table or a CTE, and join.
5. **Give each step its own time budget and its own error handling.** The worker runs its steps in order, each isolated, each with a time or batch budget. One step that fails or runs long must not stop the others. A tick that loops for too long hits the function's CPU limit and dies with work half done, so one batch per job per tick is the safe shape.
6. **Store deadlines as columns with a partial index, and sweep them every minute.** Nothing polls. A deadline column that is null means "no deadline", and the partial index only covers rows that have one.
7. **Nothing fires after an ending, or while a space is frozen or paused.** When a link between two users, a shared space or a feature ends or pauses, withdraw the reminders still waiting for it, and have the sweep check the state again when it sends.
8. **Compute time-based behaviour in each user's own time zone, and use one agreed zone for shared boundaries.** A reminder fires at 6 pm on the member's day, in the member's zone. A boundary both people share, such as "the day's question changes at 4 am", uses one zone for both, so the two members see the same day. A member who has never set a zone uses the agreed default.
9. **Skip stale reminders after a pause.** A reminder written before a freeze, or for a day that has passed, is dropped when the feature comes back. Otherwise a member gets three warnings at once, or a notice about last week.
10. **Keep the kick, if you use one, empty and the key separate.** When `pg_cron` must wake a function over HTTP, send an empty body with a random secret stored in Vault. Never use the service role key for a wake-up call. The worker decides what to do from the database, not from the call.

## How to do it
A schedule that enqueues, and a sweep that claims and acts in one set-based pass:

```sql
-- pg_cron: only enqueues.
select cron.schedule('reminders-enqueue', '* * * * *',
  $$select public.reminders_enqueue()$$);

-- The sweep step: filters first, then the batch limit.
create function public.reminders_sweep(p_limit int)
returns int
language sql
security definer
set search_path = ''
as $$
  with due as (
    select r.id, r.member_id, r.space_id
    from public.reminders r
    join public.spaces s on s.id = r.space_id
    where r.fire_at <= now()
      and s.state = 'open'                       -- nothing after an ending or a freeze
      and not exists (                           -- already done: filter before the limit
        select 1 from public.reminder_sent x where x.reminder_id = r.id)
    order by r.fire_at
    limit p_limit
  ),
  claimed as (
    insert into public.reminder_sent (reminder_id)
    select id from due
    on conflict do nothing
    returning reminder_id
  )
  select count(*)::int from claimed;
$$;
```

The worker runs `reminders_sweep` inside its own step with a batch size and a time budget, and records how many rows it handled. It then moves on to the next step even if this one returns an error.

For a time-zone rule, build a small table of the distinct zones in use, join it to the rows, and compute the local hour once per zone:

```sql
select z.zone, (now() at time zone z.zone)::time as local_time
from (select distinct time_zone as zone from public.members) z;
```

## Gotchas
- **Symptom:** a sweep took 24.4 seconds for 450 rows, with nothing due. **Cause:** an existence check against the database's time zone catalogue view ran once per row. **Fix:** resolve each distinct zone once, then join. After the fix the sweep took about 22 ms for 495 rows.
- **Symptom:** a cleanup deleted a conversation that was in the middle of its first turn. **Cause:** the row exists before its first message is written, so an "empty" conversation can still be in progress. **Fix:** delete only rows with no turn in progress and older than an hour. Move the delete into a function, and test it. See [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md) for the write order.
- **Symptom:** some members never get their reminder. **Cause:** the batch limit came before the filter that removes finished rows, so the first batch was all finished. **Fix:** filter first, then limit.
- **Symptom:** one feature's failure stops another feature's notifications. **Cause:** all steps ran in one unguarded loop. **Fix:** each step isolated with its own error handling and budget.
- **Symptom:** a reminder arrives after the link between the users ended. **Cause:** the push was queued before the ending and nothing withdrew it. **Fix:** withdraw waiting reminders on the ending, and check the state again at send time.
- **Symptom:** a reminder cannot be sent at the member's local time. **Cause:** no time zone was stored for the member, and the one schedule ran in fixed UTC. **Fix:** store the member's zone, compute the local hour from it, and use the agreed default zone only when the member has none.
- **Symptom:** a member who was first seen long ago gets several stale warnings at once. **Cause:** the sweep counted every missed interval. **Fix:** count only intervals after the member's real start, and drop reminders whose time has passed by more than a set number of hours.
- **Symptom:** a feature turned back on sends reminders for things that fell due while it was paused. **Cause:** the rows were still waiting. **Fix:** before the sweep resumes, drop or mark the rows that fell due during the pause.
- **Symptom:** the queue depth keeps growing and nothing is processed. **Cause:** the wake-up secret was never set, so the worker rejects every kick. Until setup runs, jobs queue and nothing drains them. **Fix:** a setup step that is safe to run twice, and a health view that shows queue depth, lag and dead letters.

## Checklist
- [ ] The cron job only inserts into the queue.
- [ ] Each act is claimed in the same transaction, with `on conflict do nothing`.
- [ ] Every sweep filter that removes finished or stopped rows is before the limit.
- [ ] Zone lookups happen once per distinct zone.
- [ ] Each worker step is isolated and has a budget.
- [ ] Deadlines are columns with a partial index.
- [ ] Waiting reminders are withdrawn on an ending, a freeze or a pause, and rechecked at send.
- [ ] Time rules use the member's zone, and shared boundaries use one agreed zone.
- [ ] Stale reminders are dropped after a pause.
- [ ] The queue depth, lag and dead letters are visible.

## Tests that prove it
- A duplicate-run test: run the same sweep twice and assert one send.
- A starvation test: more finished rows than the batch size, then an unfinished row, and assert the unfinished row is handled.
- A stopped-feature test: end a space with a reminder waiting, run the sweep, and assert nothing is sent.
- A time-zone test: two members in zones on either side of midnight get the reminder on their own day.
- A pause test: a reminder older than the stale window is dropped.
- A step-isolation test: one step raises, and the next step still runs.
- Database assertions are in [pgtap-database-testing](../pgtap-database-testing/SKILL.md).

## Related skills
- [postgres-time-zones-and-clocks](../postgres-time-zones-and-clocks/SKILL.md): one clock per rule, and day boundary tests.
- [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md): claims and locks shared with user actions.
- [data-lifecycle-export-purge-deletion](../data-lifecycle-export-purge-deletion/SKILL.md): purge runs as one of these steps.
- [supabase-storage-private-media](../supabase-storage-private-media/SKILL.md): the orphan upload sweep.
- [supabase-edge-functions-router](../supabase-edge-functions-router/SKILL.md): the worker is an Edge Function.
