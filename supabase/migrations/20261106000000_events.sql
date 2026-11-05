-- Events (Tracy, 2026-11-04): a holiday, an anniversary or a race day is never a concept in code.
-- It is a bundle an admin puts together from the generic pieces (switches with their windows,
-- the unlock rules and scenes that follow them, broadcast notices), tries on their own phone,
-- then publishes. An event only names the switches it owns and says how far along it is; its
-- status sets their mode: a draft's switches are off, a preview's are on only for previewers,
-- a live one's follow their schedule, and a stopped one's are off again.

-- A switch in `preview` is on only for the members who preview switches (below), in its window
-- when it has one, and off for everyone else. The public catalog shows it as off.
alter table public.switches drop constraint switches_mode_check;
alter table public.switches
  add constraint switches_mode_check check (mode in ('on', 'off', 'schedule', 'preview'));

-- Who sees switches in preview, and the day they pretend it is, so an admin tries an event on
-- their own phone in the App Store build before anyone else sees it: one row per change, never
-- changed, the newest row per member being what holds now. `day_offset` is how many days ahead
-- (or behind) of New York's today that member's switches look; everything else (check-ins,
-- weeks, the 战报) keeps the real date.
create table public.switch_previews (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  previewer boolean not null,
  day_offset int not null default 0 check (day_offset between -400 and 400),
  set_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now()
);

create index switch_previews_member on public.switch_previews (member_id, id desc);

create function public.switch_previews_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- A deleted account takes its rows (the cascade), and a deleted admin's name goes from the
  -- rows they set (set null); nothing else changes a row.
  if tg_op = 'DELETE' and not exists (select 1 from auth.users where id = old.member_id) then
    return old;
  end if;
  if tg_op = 'UPDATE' and old.set_by is not null and new.set_by is null
    and (to_jsonb(new) - 'set_by') = (to_jsonb(old) - 'set_by') then
    return new;
  end if;
  raise exception 'switch_previews is append-only' using errcode = '42501';
end;
$$;

create trigger switch_previews_append_only
  before update or delete on public.switch_previews
  for each row execute function public.switch_previews_append_only();
create trigger switch_previews_no_truncate
  before truncate on public.switch_previews
  for each statement execute function public.switch_previews_append_only();

-- Each event as it is now: its label, status and the switches it owns. One row per change,
-- never changed, the newest row per id being the event now.
create table public.events (
  id bigint generated always as identity primary key,
  event_id text not null check (public.is_catalog_id(event_id)),
  -- {"version": 1, "label": ..., "status": "draft" | "preview" | "live" | "stopped",
  --  "switches": [switch id, ...]}
  value jsonb not null check (value ? 'version'),
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now()
);

create index events_newest on public.events (event_id, id desc);

create trigger events_append_only
  before update or delete on public.events
  for each row execute function public.settings_log_append_only();
create trigger events_no_truncate
  before truncate on public.events
  for each statement execute function public.settings_log_append_only();

-- Scene takeovers: while a scene's switch is on, every squad's home shows that scene (the
-- squad's own pick stays underneath and is back when the switch goes off). A takeover scene
-- is never offered in the picker.
alter table public.scenes add column takeover boolean not null default false;
alter table public.scenes
  add constraint scenes_takeover_has_switch check (not takeover or switch_id is not null);

alter table public.switch_previews enable row level security;
alter table public.events enable row level security;
