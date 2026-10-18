-- Squads, their members, members' settings, and daily check-ins (练了 / 健康餐 /
-- 坦白放纵餐 / 今日免责声明), with their photos.
--
-- Only our own API reads and writes these tables. The app never talks to the database:
-- it calls the API, which checks every product rule (who may see what, text limits,
-- the 48-hour offline window, at most 3 squads, ...) in TypeScript. The database holds
-- only what must stay true however it is written: keys, references, uniqueness.
-- A member is a signed-in user (auth.users.id, from Supabase Auth).

-- Squads -----------------------------------------------------------------------

create table public.squads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- Null once the creator deletes their account: the squad belongs to its members.
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (squad_id, member_id)
);

create index squad_members_member_id_idx on public.squad_members (member_id);

-- Members ----------------------------------------------------------------------

-- One row per member for their own settings.
create table public.profiles (
  member_id uuid primary key references auth.users (id) on delete cascade,
  -- An IANA name such as "America/Los_Angeles" (iOS: TimeZone.current.identifier), for
  -- the member's weekly reset and their squad's 今日赛况 time. A name, not an offset:
  -- offsets change with daylight saving, names don't.
  time_zone text not null,
  updated_at timestamptz not null default now()
);

-- The database itself computes local times with `at time zone`, so a stored zone must
-- be one Postgres knows. A trigger, not a check constraint: that list can change when
-- Postgres updates its time-zone data, and a check constraint must never change its mind.
create function public.check_profile_time_zone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'unknown time zone: %', new.time_zone using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger profiles_check_time_zone
before insert or update of time_zone on public.profiles
for each row execute function public.check_profile_time_zone();

-- Check-ins --------------------------------------------------------------------

create type public.check_in_kind as enum ('trained', 'healthyMeal', 'cheatMeal', 'disclaimer');

create table public.check_ins (
  -- Made by the app, so a check-in saved offline keeps its id when it syncs, and a
  -- retry of a save is recognised by it.
  id uuid primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- The member's local calendar day the check-in counts for.
  day date not null,
  -- When the member made it, from their phone (it may sync later from offline).
  created_at timestamptz not null,
  -- When the server took it.
  received_at timestamptz not null default now(),
  kind public.check_in_kind not null,
  -- The kind's own fields (sport and minutes, meal slot, 免责声明 text, caption), as
  -- stored JSON with its shape's version at the top: {"version": 1, ...}. The API owns
  -- the shape and parses it on every read.
  payload jsonb not null check (coalesce(jsonb_typeof(payload -> 'version') = 'number', false))
);

create index check_ins_member_id_day_idx on public.check_ins (member_id, day desc);

-- At most one 今日免责声明 per member per day (Tracy, 2026-10-18). An index, not an API
-- check, so two saves at once can't both pass.
create unique index check_ins_one_disclaimer_a_day
on public.check_ins (member_id, day)
where kind = 'disclaimer';

-- A check-in's audience: the squads it was sent to, in the order the member picked.
create table public.check_in_squads (
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  -- A squad a check-in went to can't be deleted while the check-in exists.
  squad_id uuid not null references public.squads (id) on delete restrict,
  position smallint not null check (position between 1 and 3),
  primary key (check_in_id, squad_id),
  unique (check_in_id, position)
);

create index check_in_squads_squad_id_idx on public.check_in_squads (squad_id);

-- A check-in's photos, in order: position 1 is the cover. The path is the primary key,
-- so a photo belongs to at most one check-in, even when two saves race. Deleting the
-- check-in frees its photos.
create table public.check_in_photos (
  -- The object's name in the check-in-photos bucket: "<member id>/<file>".
  path text primary key,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  unique (check_in_id, position)
);

-- Photo files --------------------------------------------------------------------

-- Private bucket, with no policies: the app can't reach it directly. The API hands
-- out signed URLs to upload and to view.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'check-in-photos', 'check-in-photos', false, 10485760,
  array['image/jpeg', 'image/heic', 'image/png', 'image/webp']
);

-- Access -------------------------------------------------------------------------

-- Supabase serves the public schema to the app's tokens (the anon and authenticated
-- roles). Those roles get nothing here, and row-level security with no policies is a
-- second lock if a grant ever slips in. The API connects as a server role, which
-- bypasses both.
alter table public.squads enable row level security;
alter table public.squad_members enable row level security;
alter table public.profiles enable row level security;
alter table public.check_ins enable row level security;
alter table public.check_in_squads enable row level security;
alter table public.check_in_photos enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;
