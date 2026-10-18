-- Each member's own settings, starting with their time zone. The week resets on the
-- member's Monday and the squad's 今日赛况 goes out at a local time, so the server has
-- to know which clock each member lives on. One row per member, which only they see.
create table public.profiles (
  member_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  -- An IANA name such as "America/Los_Angeles" (iOS: TimeZone.current.identifier).
  -- A name, not an offset: offsets change with daylight saving, names don't.
  time_zone text not null,
  updated_at timestamptz not null default now()
);

-- Checked against the names Postgres itself knows, so every saved zone can be used in
-- `at time zone` later. A trigger, not a check constraint: that list can change when
-- Postgres updates its time-zone data, and a check constraint must never change its mind.
create function private.check_profile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'unknown time zone: %', new.time_zone using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_check
before insert or update on public.profiles
for each row execute function private.check_profile();

alter table public.profiles enable row level security;

create policy "Members see their own profile"
on public.profiles for select to authenticated
using (member_id = (select auth.uid()));

create policy "Members create their own profile"
on public.profiles for insert to authenticated
with check (member_id = (select auth.uid()));

create policy "Members change their own profile"
on public.profiles for update to authenticated
using (member_id = (select auth.uid()))
with check (member_id = (select auth.uid()));

-- No delete: the row goes with the account.
revoke all on public.profiles from anon;
revoke delete, truncate, references, trigger on public.profiles from authenticated;
