-- A place a member added for their squad goes when they delete their account (Tracy,
-- 2026-11-20): it is theirs, like their posts. Posts tagged with it keep their tag, since each
-- check-in keeps the place's name and coordinates itself. And a pin is kept to 4 decimals
-- (about 11 m), enough to find the place, not someone's door.

-- Places whose adder already deleted their account go now, and the rest are rounded. Only this
-- migration may, so the append-only trigger steps aside for it.
alter table public.squad_places disable trigger squad_places_append_only;
delete from public.squad_places where added_by is null;
update public.squad_places
  set latitude = round(latitude::numeric, 4)::double precision,
      longitude = round(longitude::numeric, 4)::double precision
  where latitude <> round(latitude::numeric, 4)::double precision
    or longitude <> round(longitude::numeric, 4)::double precision;
alter table public.squad_places enable trigger squad_places_append_only;

alter table public.squad_places drop constraint squad_places_added_by_fkey;
alter table public.squad_places
  alter column added_by set not null,
  add constraint squad_places_added_by_fkey
    foreign key (added_by) references auth.users (id) on delete cascade;

create or replace function public.squad_places_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's end, or the adder's account deletion, takes the place.
  if tg_op = 'DELETE'
    and (
      not exists (select 1 from public.squads where id = old.squad_id)
      or not exists (select 1 from auth.users where id = old.added_by)
    )
  then
    return old;
  end if;
  raise exception 'squad_places is append-only' using errcode = '42501';
end;
$$;
