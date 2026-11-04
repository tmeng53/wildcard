-- Switches (Tracy, 2026-11-04): one global, scheduled on/off that many things follow at once, so
-- a limited theme (the winter 雪场 and its store, a holiday later) is a row of data, never a
-- concept in code. A switch is on, off, or follows its schedule: days of every year, `MM-DD`,
-- both ends included, New York time (the end may come before the start, over New Year), so it
-- opens again next year. Scenes, unlock rules and anything later name the switch they follow.
-- A switch keeps its id and is never deleted; turn it off instead.
create table public.switches (
  id text primary key check (public.is_catalog_id(id)),
  -- What it is for, for admins; the app never shows it.
  label text not null check (label <> '' and char_length(label) <= 80),
  mode text not null check (mode in ('on', 'off', 'schedule')),
  window_start text check (window_start ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  window_end text check (window_end ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  check ((window_start is null) = (window_end is null)),
  check (mode <> 'schedule' or window_start is not null)
);

create function public.switches_keep_their_ids() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a switch is never deleted; turn it off' using errcode = '42501';
  end if;
  if new.id <> old.id then
    raise exception 'a switch''s id never changes' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger switches_keep_their_ids
  before update or delete on public.switches
  for each row execute function public.switches_keep_their_ids();

create function public.switches_no_truncate() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'switches change row by row, so each change is logged' using errcode = '42501';
end;
$$;

create trigger switches_no_truncate
  before truncate on public.switches
  for each statement execute function public.switches_no_truncate();

-- Every change to a switch: one row per inserted or changed switch with its full new value, and
-- none for an update that changed nothing. Only grows.
create table public.switch_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_switch_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.switch_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger switches_logged
  after insert on public.switches
  for each row execute function public.log_switch_change();
create trigger switches_changes_logged
  after update on public.switches
  for each row when (old is distinct from new) execute function public.log_switch_change();

create function public.switch_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'switch_events is append-only' using errcode = '42501';
end;
$$;

create trigger switch_events_append_only
  before update or delete on public.switch_events
  for each row execute function public.switch_events_append_only();
create trigger switch_events_no_truncate
  before truncate on public.switch_events
  for each statement execute function public.switch_events_append_only();

alter table public.switches enable row level security;
alter table public.switch_events enable row level security;

-- Winter (Tracy, 2026-11-04): every year from November 15 to March 31.
insert into public.switches (id, label, mode, window_start, window_end) values
  ('winter', '雪场 and POWDER DAY', 'schedule', '11-15', '03-31');

-- The scenes a squad trains on (跑道, 游泳池, 健身房, 网球场, 攀岩馆, and limited ones like the
-- winter 雪场): each one's names, its colours and its place in the picker, and, for a limited
-- one, the switch it follows: a squad may pick it only while that is on. It is data, served by
-- the API's catalog and changed through admin tools, so a new colour, name or switch needs no
-- app release; the art itself
-- ships with the app, and an app without a scene's art shows the gym in its place.
-- A scene keeps its id and is never deleted, since squads' picks and frozen 战报 name it: one
-- the picker should stop offering is marked `offered = false`.

create table public.scenes (
  id text primary key check (public.is_catalog_id(id)),
  -- The picker's order.
  position int not null check (position > 0),
  name_zh_hans text not null check (name_zh_hans <> ''),
  name_en text not null check (name_en <> ''),
  name_zh_hant text not null check (name_zh_hant <> ''),
  -- Its colours, `#RRGGBB`: the signature (the 打卡 button, the week's icons, the poster),
  -- the text drawn on it, its light wash, its text colour on light grounds, and its floor.
  signature text not null check (signature ~ '^#[0-9A-F]{6}$'),
  on_signature text not null check (on_signature ~ '^#[0-9A-F]{6}$'),
  wash text not null check (wash ~ '^#[0-9A-F]{6}$'),
  text_color text not null check (text_color ~ '^#[0-9A-F]{6}$'),
  floor text not null check (floor ~ '^#[0-9A-F]{6}$'),
  offered boolean not null default true,
  -- The switch a limited scene follows; null for one open all year.
  switch_id text references public.switches (id),
  unique (position) deferrable initially immediate
);

create function public.scenes_keep_their_ids() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a scene is never deleted; set offered = false' using errcode = '42501';
  end if;
  if new.id <> old.id then
    raise exception 'a scene''s id never changes' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger scenes_keep_their_ids
  before update or delete on public.scenes
  for each row execute function public.scenes_keep_their_ids();

create function public.scenes_no_truncate() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'scenes change row by row, so each change is logged' using errcode = '42501';
end;
$$;

create trigger scenes_no_truncate
  before truncate on public.scenes
  for each statement execute function public.scenes_no_truncate();

-- Every change to a scene, however it is made: one row per inserted or changed scene with its
-- full new value, and none for an update that changed nothing. Only grows.
create table public.scene_catalog_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_scene_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.scene_catalog_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger scenes_logged
  after insert on public.scenes
  for each row execute function public.log_scene_change();
create trigger scenes_changes_logged
  after update on public.scenes
  for each row when (old is distinct from new) execute function public.log_scene_change();

create function public.scene_catalog_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'scene_catalog_events is append-only' using errcode = '42501';
end;
$$;

create trigger scene_catalog_events_append_only
  before update or delete on public.scene_catalog_events
  for each row execute function public.scene_catalog_events_append_only();
create trigger scene_catalog_events_no_truncate
  before truncate on public.scene_catalog_events
  for each statement execute function public.scene_catalog_events_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.scenes enable row level security;
alter table public.scene_catalog_events enable row level security;

-- The first scenes: the five the app has drawn since the start, and the winter 雪场, which
-- follows the winter switch (Tracy, 2026-11-04).
insert into public.scenes (
  id, position, name_zh_hans, name_en, name_zh_hant,
  signature, on_signature, wash, text_color, floor, switch_id
) values
  ('track', 1, '跑道', 'Track', '跑道', '#E65345', '#FFFFFF', '#FCEDEB', '#B83325', '#F8DDD9', null),
  ('pool', 2, '游泳池', 'Pool', '游泳池', '#079BB8', '#FFFFFF', '#E2F5F9', '#066E83', '#CDEBF1', null),
  ('gym', 3, '健身房', 'Gym', '健身房', '#4A6C8C', '#FFFFFF', '#EDF0F4', '#3E5C78', '#DBE2E8', null),
  ('tennis', 4, '网球场', 'Tennis', '網球場', '#4F6B22', '#FFFFFF', '#EEF2E4', '#41591B', '#DDE6CC', null),
  ('climbing', 5, '攀岩馆', 'Climbing', '攀岩館', '#8E4A2C', '#FFFFFF', '#F6EDE8', '#7A3E24', '#EBDDD5', null),
  ('ski', 6, '雪场', 'Ski', '雪場', '#16384D', '#D6F1FB', '#EAF7FD', '#16384D', '#D7ECF6', 'winter');

-- A pick names a scene of the list (the five it allowed before are all on it).
alter table public.squad_scene_picks drop constraint squad_scene_picks_scene_check;
alter table public.squad_scene_picks
  add constraint squad_scene_picks_scene_fkey foreign key (scene) references public.scenes (id);
