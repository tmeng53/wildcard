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

-- A member the captain removed is logged as `removed`, apart from one who left.
alter table public.squad_membership_events drop constraint squad_membership_events_kind_check;
alter table public.squad_membership_events
  add constraint squad_membership_events_kind_check check (kind in ('joined', 'left', 'removed'));

-- Every change to a squad's name or captain, append-only and replayable: one row per change,
-- with who made it and the squad's full settings after it. `captain_id` has no reference so the
-- row outlives that member's account; the row goes with the squad or with the account of who made it.
create table public.squad_events (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  actor_id uuid not null references auth.users (id) on delete cascade,
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
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.actor_id)
    or not exists (select 1 from public.squads where id = old.squad_id)
  ) then
    return old;
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
