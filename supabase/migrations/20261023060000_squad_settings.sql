-- Squad settings (小队设置, Tracy 2026-10-22): a captain who renames the squad, removes members
-- and hands the captaincy on, and the scene the squad trains on each week, picked once a week by
-- last week's crown winner (or the captain when nobody won it). Every rule lives in the API's
-- squads module; the database keeps keys, shapes and the logs' append-only guard.

-- The captain: the creator at first, then whoever they hand it to. When the captain leaves, the
-- API names the earliest-joined member in the same transaction; when their account is deleted
-- this turns null, and the API reads the earliest-joined member as captain.
alter table public.squads
  add column captain_id uuid references auth.users (id) on delete set null;

update public.squads set captain_id = created_by;

-- A member the captain removed is logged as `removed`, apart from one who left, and each row
-- says who made the change: the member themselves, or the captain who removed them. `actor_id`
-- turns null once that account is deleted, so the row stays in the squad's log.
alter table public.squad_membership_events drop constraint squad_membership_events_kind_check;
alter table public.squad_membership_events
  add constraint squad_membership_events_kind_check check (kind in ('joined', 'left', 'removed'));
alter table public.squad_membership_events
  add column actor_id uuid references auth.users (id) on delete set null;

-- The backfill sets who made each existing row, before the guard below allows such updates, so
-- the guard is off for this one statement.
alter table public.squad_membership_events disable trigger squad_membership_events_append_only;
update public.squad_membership_events set actor_id = member_id;
alter table public.squad_membership_events enable trigger squad_membership_events_append_only;

create index squad_membership_events_actor_id_idx on public.squad_membership_events (actor_id);

-- The rows only grow: a delete goes through only once its account or squad is gone, and an
-- update only to clear who made the change once their account is gone.
create or replace function public.squad_membership_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or not exists (select 1 from public.squads where id = old.squad_id)
  ) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.actor_id is null
    and old.actor_id is not null
    and not exists (select 1 from auth.users where id = old.actor_id)
    and (new.id, new.squad_id, new.member_id, new.kind, new.at)
      = (old.id, old.squad_id, old.member_id, old.kind, old.at)
  then
    return new;
  end if;
  raise exception 'squad_membership_events is append-only' using errcode = '42501';
end;
$$;

-- Every change to a squad's name or captain, append-only and replayable: one row per change,
-- with who made it and the squad's full settings after it. The rows go only with the squad: once
-- an account is deleted, `actor_id` turns null. `captain_id` has no reference, so it keeps naming
-- a captain whose account is gone; members then read the earliest-joined member as captain.
create table public.squad_events (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  actor_id uuid references auth.users (id) on delete set null,
  kind text not null check (kind in ('created', 'renamed', 'captainChanged')),
  name text not null,
  captain_id uuid,
  at timestamptz not null default now()
);

create index squad_events_squad_id_idx on public.squad_events (squad_id);
create index squad_events_actor_id_idx on public.squad_events (actor_id);

create function public.squad_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.actor_id is null
    and old.actor_id is not null
    and not exists (select 1 from auth.users where id = old.actor_id)
    and (new.id, new.squad_id, new.kind, new.name, new.captain_id, new.at)
      is not distinct from (old.id, old.squad_id, old.kind, old.name, old.captain_id, old.at)
  then
    return new;
  end if;
  raise exception 'squad_events is append-only' using errcode = '42501';
end;
$$;

create trigger squad_events_append_only
  before update or delete on public.squad_events
  for each row execute function public.squad_events_append_only();

create trigger squad_events_no_truncate
  before truncate on public.squad_events
  for each statement execute function public.squad_events_append_only();

-- The squad's scene, one row per squad and week it was picked for, never changed: the table is
-- its own history (the year's favourite scene reads it). A squad trains on its latest pick until
-- the next; before any pick, on the track. The week is the Monday of the week the scene is for;
-- the pick opens when the week before it is awarded, Sunday at 8pm Eastern.
create table public.squad_scene_picks (
  squad_id uuid not null references public.squads (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  scene text not null check (scene in ('pool', 'track', 'gym', 'tennis', 'climbing')),
  -- Null once the picker deletes their account; the squad keeps its scene.
  picked_by uuid references auth.users (id) on delete set null,
  picked_at timestamptz not null default now(),
  primary key (squad_id, week_start)
);

create index squad_scene_picks_picked_by_idx on public.squad_scene_picks (picked_by);

create function public.squad_scene_picks_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the picker's account deletion clearing who picked, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.picked_by is null
    and old.picked_by is not null
    and not exists (select 1 from auth.users where id = old.picked_by)
    and (new.squad_id, new.week_start, new.scene, new.picked_at)
      = (old.squad_id, old.week_start, old.scene, old.picked_at)
  then
    return new;
  end if;
  raise exception 'squad_scene_picks is append-only' using errcode = '42501';
end;
$$;

create trigger squad_scene_picks_append_only
  before update or delete on public.squad_scene_picks
  for each row execute function public.squad_scene_picks_append_only();

create trigger squad_scene_picks_no_truncate
  before truncate on public.squad_scene_picks
  for each statement execute function public.squad_scene_picks_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_events enable row level security;
alter table public.squad_scene_picks enable row level security;
