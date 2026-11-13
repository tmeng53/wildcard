-- Places a squad's members add themselves (Tracy, 2026-11-12): a home gym, a park corner, a
-- friend's kitchen, anywhere Apple Maps doesn't list. The whole squad sees them and may tag
-- their own posts with them. Each is kept as it was added, never changed: the table is its own
-- log, until the squad's end takes it. As with every table, only our API reads and writes it.
create table public.squad_places (
  id uuid primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- Null once the adder deletes their account; the squad keeps the place.
  added_by uuid references auth.users (id) on delete set null,
  name text not null check (char_length(name) between 1 and 100),
  -- 吃的, 健身 or 户外: which icon it wears.
  kind text not null check (kind in ('food', 'gym', 'outdoor')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  added_at timestamptz not null
);

create index squad_places_squad_idx on public.squad_places (squad_id, added_at);
create index squad_places_added_by_idx on public.squad_places (added_by);

create function public.squad_places_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the adder's account deletion clearing who added it, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.added_by is null
    and old.added_by is not null
    and not exists (select 1 from auth.users where id = old.added_by)
    and (new.id, new.squad_id, new.name, new.kind, new.latitude, new.longitude, new.added_at)
      = (old.id, old.squad_id, old.name, old.kind, old.latitude, old.longitude, old.added_at)
  then
    return new;
  end if;
  raise exception 'squad_places is append-only' using errcode = '42501';
end;
$$;

create trigger squad_places_append_only
  before update or delete on public.squad_places
  for each row execute function public.squad_places_append_only();

create trigger squad_places_no_truncate
  before truncate on public.squad_places
  for each statement execute function public.squad_places_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_places enable row level security;

-- A squad's own place is scored like one from Apple Maps, under `squad:` and its id.
alter table public.place_ratings drop constraint place_ratings_place_key_check;
alter table public.place_ratings add constraint place_ratings_place_key_check check (
  place_key ~ '^apple:[A-Za-z0-9._-]{1,200}$'
  or place_key ~ '^squad:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);
