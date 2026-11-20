-- Day boundary test (pgTAP). Names are invented.
--
-- Two members, one in UTC+14 and one in UTC-11. Their zones are 25 hours apart,
-- so their local dates differ at every instant. A function that reads the
-- session date (UTC in CI) matches at most one of them, so the test fails at
-- any hour of the day, not only at some hours.
--
-- Everything here is inside one transaction. The zone settings and the rows
-- disappear at rollback.

begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

-- Deterministic ids for this file only.
create function pg_temp.u(tag text) returns uuid language sql immutable as
  $$ select ('bbbbbbbb-0000-0000-0000-' || lpad(substr(md5(tag), 1, 12), 12, '0'))::uuid $$;

-- The test's "today" comes from the same function the app uses, never from current_date.
create function pg_temp.today(p_member uuid) returns date language sql stable as
  $$ select public.member_today(p_member) $$;

insert into public.members (id, time_zone) values
  (pg_temp.u('east'), 'Pacific/Kiritimati'),  -- UTC+14
  (pg_temp.u('west'), 'Etc/GMT+11');         -- UTC-11

-- 1. The two members are on different dates at this instant.
select isnt(
  pg_temp.today(pg_temp.u('east')),
  pg_temp.today(pg_temp.u('west')),
  'zones 25 hours apart give different dates');

-- 2. Each member's date follows the member's own zone, under a UTC session.
select set_config('timezone', 'UTC', true);
select is(
  public.member_today(pg_temp.u('west')),
  (now() at time zone 'Etc/GMT+11')::date,
  'west member uses the member zone under a UTC session');

-- 3. The same check under a session zone far from UTC. Only the session changes.
select set_config('timezone', 'Pacific/Auckland', true);
select is(
  public.member_today(pg_temp.u('east')),
  (now() at time zone 'Pacific/Kiritimati')::date,
  'east member uses the member zone under an Auckland session');

-- 4. And under a session zone on the other side of the Pacific.
select set_config('timezone', 'America/Los_Angeles', true);
select is(
  public.member_today(pg_temp.u('west')),
  (now() at time zone 'Etc/GMT+11')::date,
  'west member uses the member zone under a Los Angeles session');

select * from finish();
rollback;
