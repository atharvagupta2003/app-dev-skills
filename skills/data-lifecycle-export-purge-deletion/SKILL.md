---
name: data-lifecycle-export-purge-deletion
description: How to handle a member's data over its life. Covers exports that contain only what that member added, hiding shared content from both people when a shared space ends, a fixed download window followed by a bounded, resumable, logged purge, account deletion that removes the leaver's content at once while keeping the other person's own content exportable, keeping evidence for open reports, kill switches that pause a feature but never block leaving or deleting, and destructive tests scoped to their own rows and refused off a local database. Load when building export, deletion, purge, retention or a feature kill switch.
---

# Data lifecycle: export, purge and deletion

## When to use this
- You are building "download my data", an account deletion, a purge job, or a retention rule.
- A shared space, group or record can end, and both people have content in it.
- A report is open and the content it names must not disappear.
- You are adding a kill switch for a feature.
- You are writing a test that deletes rows.

## Rules
1. **An export contains only what the member added.** Include the member's own messages, uploads, answers, plans and gifts. Exclude the other person's content, the other person's sealed answers, and how or by whom a shared space ended. Build the export from the same data policy that drives deletion, so the two cannot drift.
2. **When a shared space ends, hide its shared content from both people at once.** Both members lose access on the same write. Hiding for one side first leaves the other side able to see what the first can no longer see.
3. **Give a fixed download window, then purge.** The window is a setting row (for example 30 days). During the window both members can download what they added. After it, a job purges the space. Make the window a row so it can change without a deploy.
4. **Make the purge bounded, resumable, idempotent and logged.** Bounded: a set number of spaces per tick. Resumable: a stopped run leaves the rest for the next tick. Idempotent: a repeat run changes nothing. Logged: one append-only row per purged space holding counts only, never ids or content.
5. **Delete objects before rows, and refuse to delete rows while objects remain.** If a storage object cannot be removed, the rows stay and the next tick retries. (See [supabase-storage-private-media](../supabase-storage-private-media/SKILL.md).)
6. **On account deletion, remove the leaver's own content at once.** The leaver's messages, uploads, plans and answers go in the same deletion. The other person's space closes with a neutral notice that gives no reason.
7. **Keep the other person's own content exportable after the leaver deletes.** Some of their content hangs off the leaver's rows and would cascade away. Before the cascade, copy exactly the survivor's parts into a copy table, and have the export read that copy for those parts.
8. **Keep evidence for every open report.** Content named by an open report is held: hidden from normal reads, its object undeletable, and a copy saved at report time. The hold ends when the report is resolved and its retention period has passed. The evidence bucket is separate from the member's bucket.
9. **Give each feature a kill switch that pauses it and nothing else.** A settings row turns a feature off. Off means the feature is paused like a frozen space: reads and writes refuse, reminders stop. Leaving, blocking, reporting, downloading and deleting never read the switch. People must always be able to get out and get their data.
10. **Make each destructive step a no-op when repeated.** Deletion runs in order: a fence on new uploads, storage objects, then the rows in one transaction, then the auth user. Each step checks whether it is already done. A retry after a failure finishes the job.
11. **Use a data policy table that every uuid-bearing table must appear in.** One row per table: which columns hold a member's id, what deletion does, what may survive (for example reports about the member), and whether export includes it. A new table with no row fails the test suite until someone decides.

## How to do it
A deletion skeleton with the order that matters:

```sql
create function public.account_delete_rows(p_member uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Refuse while any stored object still names this member.
  if exists (select 1 from public.media_objects where owner_id = p_member) then
    raise exception 'deletion_objects_remain';
  end if;

  -- Copy the survivor's own parts before the cascade removes them.
  insert into public.space_member_exports (space_id, member_id, content)
  select m.space_id, m.other_member_id, jsonb_agg(n.body)
    from public.space_notes n
    join public.space_members m on m.space_id = n.space_id and m.member_id = p_member
   where n.author_id = p_member
   group by m.space_id, m.other_member_id;

  delete from public.members where id = p_member;  -- cascades and triggers end shared state

  -- Deep check: nothing outside the survivors may still name the member.
  if exists (
    select 1 from public.space_notes where author_id = p_member
  ) then
    raise exception 'deletion_incomplete';
  end if;
end;
$$;
```

Storage objects are removed by the caller before this function runs, and the function refuses if any remain. The caller then deletes the auth user. Each step can run again safely.

The data policy table is a plain table with one row per public table: `table_name`, `member_columns`, `on_delete` (`delete`, `clear`, `keep`), `export` (`rows`, `custom`, `excluded`) and `reason`. A pgTAP test lists every table with a uuid column and fails when a table is missing from it.

## Gotchas
- **Symptom:** a member's account deletion appears to succeed, but their photos are still in storage with no row to find them. **Cause:** the photo deletion was best effort, its errors were swallowed, and the auth user was deleted anyway. **Fix:** storage errors abort the deletion step, and the retry finishes it.
- **Symptom:** deletion failed in production until someone changed a foreign key by hand. **Cause:** the fix lived outside the migrations, so the repository did not match production. **Fix:** every change to a deletion path is a migration, and the nightly drift check catches manual edits.
- **Symptom:** the export contains photo paths but the member cannot open their photos. **Cause:** the export listed storage paths, not links. **Fix:** the export holds short-lived signed links, never paths.
- **Symptom:** the export is missing reports and gifts. **Cause:** the export was written by hand and nobody updated it when a table was added. **Fix:** the export is generated from the data policy table, and a missing row fails the test.
- **Risk:** an open report loses its evidence when the uploader deletes the photo. **Cause:** the report pointed at the only copy. **Fix:** copy the evidence at report time, and let the report keep its copy. (Found in design review, not in a shipped incident.)
- **Symptom:** a purge races with a report on the same space. **Cause:** no ordering between them. **Fix:** a report takes a share lock on the space and is refused once the purge has started, so a report either lands first with its copy or is refused cleanly.
- **Risk:** a destructive test deletes data outside its own fixtures. **Cause:** the test ran against every space, not the ones it created. **Fix:** tests create their own spaces, act only on those, and refuse to run unless the database host is local. (Adopted as a review fix before any shared testing.)

## Checklist
- [ ] The export is built from what the member added, generated from the data policy table.
- [ ] The window is a settings row. Hiding happens on the same write for both people.
- [ ] The purge is bounded, resumable, idempotent and logs counts only.
- [ ] Storage objects are removed before rows, and rows refuse to go while objects remain.
- [ ] Account deletion removes the leaver's content and keeps the survivor's own copy.
- [ ] Open reports hold their content and their evidence copy.
- [ ] The kill switch is read by feature reads and writes only, never by leave, block, report, download or delete.
- [ ] Each destructive step is a no-op when repeated.
- [ ] Destructive tests act only on their own rows and refuse non-local databases.

## Tests that prove it
- An export test: the member's content is present, the other person's content and sealed answers are absent, and no field holds a storage path.
- A data policy test: every table with a uuid column has a policy row, and every foreign key to members is named.
- A purge test: run it twice, assert one set of effects, and assert a failed object delete leaves the rows.
- A deletion test: after deletion, a deep scan of every uuid column finds nothing that names the member, except the survivor's own rows.
- A kill switch test: with the switch off, reads refuse, while leave, block, report, download and delete still succeed.
- A safety test for the test suite itself: the destructive helper refuses a non-local URL.
- Harness details are in [pgtap-database-testing](../pgtap-database-testing/SKILL.md) and [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md).

## Related skills
- [supabase-storage-private-media](../supabase-storage-private-media/SKILL.md): object deletion and orphan cleanup.
- [background-jobs-and-sweeps](../background-jobs-and-sweeps/SKILL.md): the purge runs as a worker step.
- [privacy-sealing-and-inference](../privacy-sealing-and-inference/SKILL.md): what an export must never reveal.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md): kill switches and audiences in general.
