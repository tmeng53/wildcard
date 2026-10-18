-- Check-in wire format from contract PR #14: up to 3 photos with a cover, the full
-- sport list, and a member's own sport (其他).

-- Sports ------------------------------------------------------------------------

-- The 52 listed sports (`Sport` in ios/Packages/Contracts). A new sport is a contract
-- change and a new migration here; a newer app's unknown sport is refused on save.
create function private.is_sport(sport text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select sport in (
    'run', 'walk', 'hike', 'trailRun',
    'strength', 'crossfit', 'hyrox', 'kettlebell',
    'spin', 'elliptical', 'rowing', 'hiit', 'jumpRope', 'aerobics',
    'yoga', 'matPilates', 'reformerPilates', 'barre', 'stretching',
    'swim', 'surf', 'paddleboard', 'kayak',
    'tennis', 'badminton', 'pickleball', 'tableTennis', 'squash',
    'basketball', 'soccer', 'volleyball', 'golf', 'baseballSoftball', 'ultimate',
    'roadCycling', 'mountainBiking',
    'climb', 'ski', 'snowboard', 'skate',
    'boxing', 'kickboxing', 'jiuJitsu', 'martialArts',
    'dance',
    'dogWalk', 'walkCommute', 'bikeCommute', 'deepClean', 'moving', 'strollerWalk', 'gardening'
  );
$$;

-- What was trained (`Activity`): `"sport": "<listed sport>"`, or `"sport": "custom"` with
-- a `customSport` name of 1 to 20 characters on one line. The app holds the exact 20;
-- the database caps it loosely at 500 code points, as it does other text.
create function private.is_activity(payload jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(case
    when payload ->> 'sport' = 'custom' then
      private.is_short_text(payload -> 'customSport', one_line => true)
      and char_length(payload ->> 'customSport') <= 500
    else
      private.is_sport(payload ->> 'sport') and not payload ? 'customSport'
  end, false);
$$;

-- Photos ------------------------------------------------------------------------

-- `photos` (`Photos`): 1 to 3 distinct {"path": "<member id>/..."}, the first being the
-- cover. Members only point at their own uploads.
create function private.photos_are_valid(photos jsonb, member uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(photos) = 'array'
    and jsonb_array_length(photos) between 1 and 3
    and not exists (
      select 1 from jsonb_array_elements(photos) p
      where jsonb_typeof(p) <> 'object'
         or (select count(*) from jsonb_object_keys(p) k where k <> 'path') > 0
         or jsonb_typeof(p -> 'path') is distinct from 'string'
         or not starts_with(p ->> 'path', member::text || '/')
         or char_length(p ->> 'path') <= char_length(member::text || '/')
    )
    and (select count(distinct p ->> 'path') from jsonb_array_elements(photos) p)
        = jsonb_array_length(photos);
$$;

-- Every photo path a saved check-in points at, one row each. The primary key is what
-- makes a photo belong to one check-in: two check-ins (even saved at the same moment)
-- can't both claim it. Bookkeeping only, so it lives in the unexposed schema.
create table private.check_in_photos (
  path text primary key,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  unique (check_in_id, position)
);

-- The payload rules, now with `photos` and the new sports. Rows saved in the old
-- shape move to the new one below. A rule that can't be decided (a missing or JSON
-- null field) counts as broken: a check constraint lets a null through.
create or replace function private.check_in_payload_is_valid(
  kind public.check_in_kind, payload jsonb, member uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_typeof(payload) = 'object'
    and case
      when kind = 'trained' then
        payload ?& array['sport', 'minutes']
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('sport', 'customSport', 'minutes', 'photos', 'caption')) = 0
        and private.is_activity(payload)
        and jsonb_typeof(payload -> 'minutes') = 'number'
        and (payload ->> 'minutes') ~ '^[0-9]+$'
        and (payload ->> 'minutes')::int between 1 and 600
      when kind in ('healthyMeal', 'cheatMeal') then
        payload ? 'slot'
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('slot', 'photos', 'caption')) = 0
        and payload ->> 'slot' in ('breakfast', 'lunch', 'dinner', 'snack')
      when kind = 'disclaimer' then
        payload ? 'text'
        and (select count(*) from jsonb_object_keys(payload) k where k <> 'text') = 0
        and private.is_short_text(payload -> 'text', one_line => false)
    end
    and (not payload ? 'caption' or private.is_short_text(payload -> 'caption', one_line => true))
    and (not payload ? 'photos' or private.photos_are_valid(payload -> 'photos', member)), false);
$$;

-- Rows saved before this change: `photo` becomes a one-photo `photos`, and the sports
-- that were split (pilates, cycle) or dropped (ball, other) take their nearest new one.
create function pg_temp.upgrade_payload(kind public.check_in_kind, payload jsonb)
returns jsonb
language sql
as $$
  select case
    when kind = 'trained' and p ->> 'sport' in ('ball', 'other') then
      jsonb_set(p, '{sport}', '"custom"')
        || jsonb_build_object('customSport', case p ->> 'sport' when 'ball' then '球类' else '其他' end)
    when kind = 'trained' and p ->> 'sport' = 'pilates' then jsonb_set(p, '{sport}', '"matPilates"')
    when kind = 'trained' and p ->> 'sport' = 'cycle' then jsonb_set(p, '{sport}', '"roadCycling"')
    else p
  end
  from (
    select case when payload ? 'photo'
      then (payload - 'photo') || jsonb_build_object('photos', jsonb_build_array(payload -> 'photo'))
      else payload
    end as p
  ) upgraded;
$$;

update public.check_ins
set payload = pg_temp.upgrade_payload(kind, payload)
where payload <> pg_temp.upgrade_payload(kind, payload);

insert into private.check_in_photos (path, check_in_id, position)
select p.value ->> 'path', c.id, p.ordinality
from public.check_ins c, jsonb_array_elements(c.payload -> 'photos') with ordinality p
where c.payload ? 'photos';

-- In use means a saved check-in points at it, from the table above.
create or replace function private.photo_is_in_use(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.check_in_photos p where p.path = photo_is_in_use.path);
$$;

create or replace function private.can_see_photo(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.check_in_photos p
    where p.path = can_see_photo.path
      and private.can_see_check_in(p.check_in_id)
  );
$$;

-- Saving: every photo in the member's own folder must already be uploaded. Paths in
-- another folder fail the payload check without saying whether that photo exists.
-- Whether a photo is already taken is left to the primary key above, which also holds
-- when two saves race.
create or replace function private.stamp_check_in()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.received_at := now();
  if new.created_at > now() + interval '5 minutes'
     or new.created_at < now() - interval '48 hours' then
    raise exception 'a check-in''s createdAt must be within the last 48 hours, not in the future'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_array_elements(
      case when jsonb_typeof(new.payload -> 'photos') = 'array' then new.payload -> 'photos' else '[]' end
    ) p
    where starts_with(p ->> 'path', new.member_id::text || '/')
      and not private.photo_is_uploaded(p ->> 'path')
  ) then
    raise exception 'upload a check-in''s photos before saving it' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- After the payload check passes, claim the check-in's photos.
create function private.claim_check_in_photos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.check_in_photos (path, check_in_id, position)
  select p.value ->> 'path', new.id, p.ordinality
  from jsonb_array_elements(coalesce(new.payload -> 'photos', '[]')) with ordinality p;
  return null;
exception
  when unique_violation then
    raise exception 'another check-in already uses this photo' using errcode = '23505';
end;
$$;

create trigger check_ins_claim_photos
after insert on public.check_ins
for each row execute function private.claim_check_in_photos();
