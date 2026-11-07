-- A squad's time zone (小队时区): the clock its squad-wide moments keep, the 战报 and awards
-- freezing Sunday 8pm and the coach's daily wake with its 战术板. Everything about one member (their
-- day, their 6pm push, their coach's note) keeps their own profile's zone. Each row is one setting
-- and the week it counts from (a Monday); the zone of a week is the newest row from that week or
-- before, and a squad with none keeps New York, as every squad did before. A squad's first row
-- counts from the week it was made, a captain's change from the next week, so a week never
-- changes its clock while the squad plays it. Never changed: the table is its own log.
create table public.squad_time_zones (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  time_zone text not null,
  week_start date not null check (extract(isodow from week_start) = 1),
  -- Null once the setter deletes their account, and for the rows this migration starts with.
  set_by uuid references auth.users (id) on delete set null,
  set_at timestamptz not null default now()
);

create index squad_time_zones_squad_idx on public.squad_time_zones (squad_id, week_start, id);
create index squad_time_zones_set_by_idx on public.squad_time_zones (set_by);

-- A zone Postgres knows, as a profile's must be (the same check).
create trigger squad_time_zones_check_time_zone
before insert on public.squad_time_zones
for each row execute function public.check_profile_time_zone();

create function public.squad_time_zones_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the setter's account deletion clearing who set it, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.set_by is null
    and old.set_by is not null
    and not exists (select 1 from auth.users where id = old.set_by)
    and (new.id, new.squad_id, new.time_zone, new.week_start, new.set_at)
      = (old.id, old.squad_id, old.time_zone, old.week_start, old.set_at)
  then
    return new;
  end if;
  raise exception 'squad_time_zones is append-only' using errcode = '42501';
end;
$$;

create trigger squad_time_zones_append_only
  before update or delete on public.squad_time_zones
  for each row execute function public.squad_time_zones_append_only();

create trigger squad_time_zones_no_truncate
  before truncate on public.squad_time_zones
  for each statement execute function public.squad_time_zones_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_time_zones enable row level security;

-- Squads made before this keep New York through this week, then follow their captain's own zone
-- from Monday 2026-11-09, as if the captain had set it now.
insert into public.squad_time_zones (squad_id, time_zone, week_start)
select squads.id, profiles.time_zone, date '2026-11-09'
from public.squads
join public.profiles on profiles.member_id = squads.captain_id
where profiles.time_zone <> 'America/New_York';
