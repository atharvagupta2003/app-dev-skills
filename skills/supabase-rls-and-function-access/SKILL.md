---
name: supabase-rls-and-function-access
description: How to decide who can read and write each table and function in Supabase. Covers row level security on every table with deny by default, giving members no direct access to sensitive tables and reading through functions that take identity from the session, security definer rules, no string interpolation into filters, additive response shapes, enums and settings rows, and why an else branch must never grant access. Load when writing RLS policies, RPCs, security definer functions or any read path.
---

# Supabase RLS and function access

## When to use this
- You are adding a table, a policy, an RPC or a security definer function.
- A feature holds sensitive data (location, photos, private answers, money, reports) and you need to decide how members read it.
- You are changing a response shape that an app build already parses.
- You are writing a SQL `case` or an `if` with an `else` that decides whether someone may see or do something.

## Rules
1. **Enable row level security on every table, deny by default, and add policies one command at a time.** A profile table whose select policy returned the whole row, including exact coordinates, let anyone the member had ever matched read those coordinates. Row level security cannot hide columns, so a sensitive column must sit in a table the member cannot select, or behind a function that leaves it out.
2. **For sensitive features, give members no direct table access.** Put the rows in tables with no member policy at all. Members read through functions that find the caller's row from `auth.uid()`. A member who is not part of the space gets an empty result, never an error that confirms the id exists.
3. **Never pass an owner id into a member function.** No space id or member id is an argument to a member RPC. The function resolves "my space" from the session. Otherwise any signed-in user can ask about someone else by changing one argument.
4. **Security definer functions set an empty search path, schema-qualify every name, and revoke execute before granting.** `security definer` runs as the owner, so a search path that an attacker can influence runs their code with owner rights. Revoke from `public`, `anon` and `authenticated`, then grant only to the role that needs it.
5. **Never interpolate a string into a filter.** One function built a filter expression from ids in the request body and ran it with the service role, which skips RLS. Use typed arguments to functions, or validate every id as a UUID before it goes anywhere, and let the database bind the values.
6. **Take identity only from the verified token.** The Edge Function router sets the user id from `auth.getUser()` on the bearer token. Any `user_id` in the body is ignored or refused. Never read identity from a header a client can set.
7. **Response shapes only add fields.** An app build from last month still parses yesterday's response. Add new keys; never rename, remove or change the meaning of a key. Keep the old consent texts and old enum values readable so old builds still record and read what they recorded.
8. **Closed vocabularies are enums, and product numbers are rows.** A status with a fixed list of values is a Postgres enum, not `text` with a `CHECK`. A limit, price, weight or threshold is a row. A missing row means the feature is off, never a default number in code.
9. **No else branch may grant access.** Write the allow condition, and make every other case refuse. A rule that treated a missing category as "matches everyone" let a single unanswered field pass every member through the filter.

## How to do it
A member-facing read of a sensitive table looks like this. The table has RLS on and no member policy. The function is the only way in.

```sql
create table public.space_notes (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces (id),
  author_id uuid not null references auth.users (id),
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.space_notes enable row level security;
-- No policy for authenticated. Deny by default.

create function public.list_space_notes()
returns setof public.space_notes
language sql
stable
security definer
set search_path = ''
as $$
  select n.*
  from public.space_notes n
  join public.space_members m
    on m.space_id = n.space_id and m.member_id = (select auth.uid())
  order by n.created_at;
$$;

revoke execute on function public.list_space_notes() from public, anon;
grant execute on function public.list_space_notes() to authenticated;
```

The function takes no id. It answers only for the caller's own space. A new feature gets the same shape: a table with no member policy, one function per read, and a test that calls each function as a member of a different space.

## Gotchas
- **Symptom:** a member can read a column they should not see, even though the policy looks right. **Cause:** row level security is per row. The policy allowed the row, so every column came with it. **Fix:** move the column out of the readable table, or read it through a function that omits it.
- **Symptom:** a table has RLS on but nobody can read it, not even the owner. **Cause:** the event trigger that enables RLS on new tables creates no policy. **Fix:** that is the intended deny default. Add an explicit policy or a function for each read you need. The same trigger was also callable by `anon` through an RPC, which should be revoked.
- **Symptom:** a comment in a migration says a column is owner only. **Cause:** the comment was wrong and nothing enforced it. **Fix:** a comment is not a control. Test the rule with a query made as another user.
- **Symptom:** a block does not hide a profile. **Cause:** the block was checked in one function but not in the read policy. **Fix:** every read path that shows another member checks blocks in the same place the visibility is decided (see [privacy-sealing-and-inference](../privacy-sealing-and-inference/SKILL.md)).
- **Symptom:** a feature works for the owner and returns nothing for a different member, without an error. **Cause:** the function filters by the caller's membership. **Fix:** that is correct. Test it as a stranger and expect zero rows.
- **Symptom:** an app update breaks on an old build after a backend change. **Cause:** a key was renamed or an enum value was removed. **Fix:** add the new key beside the old one, and keep old enum values readable.
- **Symptom:** a `case` returns a permissive value when it meets a value it does not know. **Cause:** the `else` branch granted. **Fix:** list the allowed values, return refusal in `else`, and test an unknown value.

## Checklist
- [ ] RLS is enabled on the new table, and each policy is written for one command.
- [ ] Sensitive rows have no member policy. Members read through a function.
- [ ] No owner id is an argument to a member function.
- [ ] Each security definer function sets `search_path = ''`, qualifies names, and revokes before granting.
- [ ] No filter is built from strings. Ids are typed or validated.
- [ ] Identity comes from the token only.
- [ ] Response changes are additive.
- [ ] Each closed list is an enum. Each number is a row. A missing row turns the feature off.
- [ ] Every `else` refuses.

## Tests that prove it
- For each function, call it as the owner, as a member of a different space, as a stranger and as `anon`. Expect the rows for the owner and zero rows or a refusal for the others. Assert the refusal does not name the resource.
- A guard test that lists every function reading a sensitive table, and fails when a new reader appears. See [privacy-sealing-and-inference](../privacy-sealing-and-inference/SKILL.md).
- A test that an unknown enum value or an absent settings row refuses rather than allows.
- Full suite details are in [pgtap-database-testing](../pgtap-database-testing/SKILL.md).

## Related skills
- [supabase-migrations-discipline](../supabase-migrations-discipline/SKILL.md): the grants check that runs on every migration.
- [supabase-edge-functions-router](../supabase-edge-functions-router/SKILL.md): where identity is read from the token.
- [supabase-storage-private-media](../supabase-storage-private-media/SKILL.md): the same rules for objects in buckets.
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md): how the access tests are written.
