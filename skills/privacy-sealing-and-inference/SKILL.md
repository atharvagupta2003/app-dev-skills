---
name: privacy-sealing-and-inference
description: How to keep content hidden until both people have answered or a date has passed, and stop it leaking through other channels. Covers one function that decides every reveal, a guard test that lists every reader of a sealed table, checks for history, exports, realtime and push payloads, counts, error messages and timing, private skips that cannot be inferred, private marks kept in their own table, and aggregates from private answers that can leak when samples are small or recomputed on demand. Load when building "sealed until both answer", "revealed on a date", private skips, private marks or any score made from two people's private data.
---

# Privacy: sealing and inference

## When to use this
- Content must stay hidden from one person until both have answered, or until a date or time passes.
- A member may skip or decline something, and the skip must stay private.
- A member keeps a private mark about something the other person owns, such as "already bought".
- A summary, score, award or count is computed from two people's private answers.
- A feature adds a new read of an existing table that holds sealed content.

## Rules
1. **One function decides every reveal.** A single SQL function takes the sealed row and the viewer and returns what that viewer may see: the partner's text only when both have answered, nothing otherwise. Every read of the sealed content goes through it. Other functions never read the raw answers.
2. **A guard test lists every function that reads the sealed table, directly or through another function, and fails when a new one appears.** The test expects a fixed list. Adding a reader means changing the list in the same pull request, which makes the reviewer look at it.
3. **Check every channel, not just the read.** Sealed content can leak through history, exports, realtime payloads, push payloads, counts, error messages and timing. Test each one for every sealed field.
4. **A private skip must not be inferable from history.** Store a skip as an answer row with a skipped flag, the same shape as a normal answer, so "answered or skipped" is simply "a row exists". A history list must show a day only when the viewer touched it or the other person wrote an answer, so a skip never appears as an absence.
5. **Keep a private mark in its own table that the other person's reads never touch.** The list belongs to the owner, and the mark belongs to the other person. Put the mark in a separate table. The owner's read is then the same query whether or not anything is marked, and the owner's output is byte for byte the same before and after.
6. **Freeze the snapshot and limit recomputation for any aggregate over private answers.** A result computed on demand from two people's answers can be probed: change one answer, recompute, and see the result move. Compute the result once, store it as a snapshot, require a minimum sample before showing any band, and cap how many answers a person can write per day.
7. **Show bands, not scores, and only for dimensions with enough shared questions.** A band tells the viewer "close", "mixed" or "far" for a dimension. A raw score or a count of shared questions can reconstruct the answers. Hide a dimension that has fewer than the minimum shared questions, and never say which partner caused it.
8. **Count and award only what both sides can see.** An award, a streak or a total counts only events both people can see. A private log that one person keeps must not add to a shared count, or it reveals that the log exists. Why: a "first photo" award was awarded for a photo still held for review, which only its uploader could see.
9. **Decide visibility of profile fields in one SQL function that every read uses.** The same function serves the full profile, the card summary and the report snapshot, so a field hidden in one place cannot appear in another.
10. **Keep sensitive text out of push payloads and logs.** Push copy is generic: no name, no answer, no preview. The payload carries only the ids the app needs to route. Logs never carry answer values.

## How to do it
A sealing view, the only reader of answers:

```sql
create function public.daily_question_view(p_space uuid, p_day date, p_viewer uuid)
returns table (my_answer text, partner_answer text, my_status text, revealed boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with a as (
    select
      max(body) filter (where member_id = p_viewer and body is not null) as mine,
      max(body) filter (where member_id <> p_viewer and body is not null) as theirs,
      bool_or(member_id = p_viewer and skipped) as i_skipped,
      count(*) filter (where body is not null) as n_answers
    from public.question_answers
    where space_id = p_space and day = p_day
  )
  select
    a.mine,
    case when a.n_answers = 2 then a.theirs end,          -- reveal only when both answered
    case when a.mine is not null then 'answered'
         when a.i_skipped then 'skipped'
         else 'open' end,
    a.n_answers = 2
  from a;
$$;

revoke execute on function public.daily_question_view(uuid, date, uuid) from public, anon, authenticated;
```

The app calls a member function that resolves the space and the viewer from the session and then calls this view. The guard test lists every function whose body contains `question_answers`, and fails on any name not in its expected list.

For a check that is "sealed until a time", the same pattern holds: one view compares the current time with the reveal time and returns the sealed text only after it. Send the reveal on the same Realtime topic to both people at the same moment, and send an unrevealed write only to its author.

## Gotchas
- **Symptom:** a history list showed a day the member never touched, and that revealed a skip. **Cause:** history listed every day that had any row. **Fix:** list a day only when the viewer touched it or the other person wrote an answer, and route history through the sealing view so the guard test catches any new direct join.
- **Symptom:** a push named the other member and what they did. **Cause:** the copy was written with the name. **Fix:** generic copy and a payload of ids only. Lock screens show the copy, so a name is a disclosure.
- **Risk:** a count of answers reveals that a skip happened. **Cause:** a skip stored as no row at all would look like an unanswered day. **Fix:** store the skip as a row with a skipped flag, so "answered or skipped" is one check. (Design rule.)
- **Symptom:** per area results made from two members' private answers revealed the other member's exact answers. **Cause:** the results were recomputed on every read, and an area with two questions gave a viewer a small set of combinations to test. A reviewer tried all twelve combinations, and exactly one produced the top band. **Fix:** a frozen snapshot, a minimum sample, and a daily cap on writes.
- **Symptom:** a "first photo" award was awarded for a photo still held for review. **Cause:** the count included a photo that only its uploader could see. **Fix:** count only photos both members can see, and test the award with a photo in review.
- **Risk:** the owner's view changes shape when the partner marks an item. **Cause:** the mark sat on the owner's row. **Fix:** the mark lives in its own table, and the owner's view never reads it. (Design rule, tested by a byte-for-byte comparison.)
- **Risk:** an error message reveals that content exists. **Cause:** "forbidden" differs from "not found" depending on whether the id is real. **Fix:** a stranger gets the same empty result or refusal whether or not the id exists.
- **Symptom:** a comment in a migration says a column is private, and it is not. **Cause:** comments are not controls. **Fix:** test the rule with a query made as the other user.
- **Risk, not yet tested:** timing reveals a sealed answer. **Cause:** a reveal path does extra work only when the partner has answered. **Fix:** do the same work on every path, or document the timing as a known limit.

## Checklist
- [ ] One function decides the reveal, and every read of the sealed table goes through it.
- [ ] The guard test lists every reader, direct and indirect, and fails on a new one.
- [ ] History, exports, Realtime, push payloads, counts, errors and timing were each checked.
- [ ] A skip is stored as a row, and history does not show absences.
- [ ] A private mark lives in its own table.
- [ ] Aggregates are snapshots with a minimum sample and a daily write cap.
- [ ] Bands are shown, not scores, and small dimensions are hidden.
- [ ] Awards and counts include only what both sides can see.
- [ ] Push copy and payloads carry no names or answers.

## Tests that prove it
- A guard test over the database's function source, listing the expected readers of each sealed table. It fails on any addition.
- For each channel (history, export, a Realtime subscription, a push payload, a count, an error), a test that the sealed text is absent before both answer and present after.
- A test that a skip is indistinguishable from an open day to the other person.
- A test that the owner's view is byte for byte the same before and after a private mark, including under concurrent reads.
- A test that a small sample returns no band, and that two writes in quick succession do not change a frozen snapshot.
- Database harness details are in [pgtap-database-testing](../pgtap-database-testing/SKILL.md).

## Related skills
- [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md): the function-only access pattern this depends on.
- [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md): two answers at once must reveal exactly once.
- [data-lifecycle-export-purge-deletion](../data-lifecycle-export-purge-deletion/SKILL.md): exports must exclude the other person's sealed content.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): reveal times and withdrawn reminders.
