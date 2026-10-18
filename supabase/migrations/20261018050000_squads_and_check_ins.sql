-- Squads, their members, and daily check-ins (练了 / 吃得干净 / 今日免责声明).
-- Mirrors the check-in contract in ios/Packages/Contracts (wire version 1).
-- A member is a signed-in user (auth.users.id). A check-in belongs to its member, who
-- sends it to one or more of their squads; members of those squads see it.

-- Helpers that row-level policies call live outside the API's exposed schemas.
create schema private;
grant usage on schema private to authenticated;

-- Squads -----------------------------------------------------------------------

create table public.squads (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  -- Null once the creator deletes their account: the squad belongs to its members.
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (squad_id, member_id)
);

create index squad_members_member_id_idx on public.squad_members (member_id);

-- A member is in at most 3 squads. The lock keeps two joins at once from both passing.
create function private.limit_squads_per_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('squad_members'), hashtext(new.member_id::text));
  if (select count(*) from public.squad_members where member_id = new.member_id) >= 3 then
    raise exception 'a member can be in at most 3 squads' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger squad_members_limit
before insert on public.squad_members
for each row execute function private.limit_squads_per_member();

-- Security definer so policies on squad_members can ask about squad_members
-- without recursing into their own policy.
create function private.is_squad_member(squad uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.squad_members
    where squad_id = squad and member_id = (select auth.uid())
  );
$$;

revoke execute on function private.is_squad_member(uuid) from public;
grant execute on function private.is_squad_member(uuid) to authenticated;

-- Whoever creates a squad is its first member. Joining by invite comes with the
-- invite flow; until then members are added only through this trigger.
create function private.add_squad_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.squad_members (squad_id, member_id) values (new.id, new.created_by);
  return new;
end;
$$;

create trigger squads_add_creator
after insert on public.squads
for each row execute function private.add_squad_creator();

alter table public.squads enable row level security;
alter table public.squad_members enable row level security;

-- The creator also matches, so creating a squad can return the new row: the trigger
-- that adds them as a member runs after the row is checked.
create policy "Members see their squads"
on public.squads for select to authenticated
using (created_by = (select auth.uid()) or (select private.is_squad_member(id)));

create policy "Signed-in users create squads they own"
on public.squads for insert to authenticated
with check (created_by = (select auth.uid()));

create policy "The creator renames the squad"
on public.squads for update to authenticated
using (created_by = (select auth.uid()))
with check (created_by = (select auth.uid()));

create policy "Members see who is in their squads"
on public.squad_members for select to authenticated
using ((select private.is_squad_member(squad_id)));

create policy "Members leave squads"
on public.squad_members for delete to authenticated
using (member_id = (select auth.uid()));

-- Check-ins --------------------------------------------------------------------

-- 练了, 健康餐, 放纵餐忏悔, 今日免责声明.
create type public.check_in_kind as enum ('trained', 'healthyMeal', 'cheatMeal', 'disclaimer');

-- A 免责声明 or a caption: trimmed, 1 to 40 characters as people see them; a caption
-- is also one line (the contract lets a 免责声明 span lines). Postgres counts code
-- points, not what people see (a family emoji is 1 character but 7 code points), so
-- it holds a loose cap of 400; the app holds the exact limit.
create function private.is_short_text(value jsonb, one_line boolean)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) = 'string'
    and char_length(value #>> '{}') between 1 and 400
    and value #>> '{}' = btrim(value #>> '{}', E' \t\n\r')
    and (not one_line or (strpos(value #>> '{}', E'\n') = 0 and strpos(value #>> '{}', E'\r') = 0));
$$;

-- The kind-specific object from the wire JSON (`training`, `meal` or `disclaimer`),
-- checked against the same rules as the Swift contract.
create function private.check_in_payload_is_valid(
  kind public.check_in_kind, payload jsonb, member uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(payload) = 'object'
    and case
      when kind = 'trained' then
        payload ?& array['sport', 'minutes']
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('sport', 'minutes', 'photo', 'caption')) = 0
        and payload ->> 'sport' in (
          'run', 'strength', 'yoga', 'pilates', 'swim', 'cycle',
          'ball', 'climb', 'hike', 'dance', 'other'
        )
        and jsonb_typeof(payload -> 'minutes') = 'number'
        and (payload ->> 'minutes') ~ '^[0-9]+$'
        and (payload ->> 'minutes')::int between 1 and 600
      when kind in ('healthyMeal', 'cheatMeal') then
        payload ? 'slot'
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('slot', 'photo', 'caption')) = 0
        and payload ->> 'slot' in ('breakfast', 'lunch', 'dinner', 'snack')
      when kind = 'disclaimer' then
        payload ? 'text'
        and (select count(*) from jsonb_object_keys(payload) k where k <> 'text') = 0
        and private.is_short_text(payload -> 'text', one_line => false)
    end
    and (not payload ? 'caption' or private.is_short_text(payload -> 'caption', one_line => true))
    -- A photo is {"path": "<member id>/..."}: members only point at their own uploads.
    and (
      not payload ? 'photo'
      or (
        jsonb_typeof(payload -> 'photo') = 'object'
        and (select count(*) from jsonb_object_keys(payload -> 'photo') k where k <> 'path') = 0
        and jsonb_typeof(payload -> 'photo' -> 'path') = 'string'
        and starts_with(payload -> 'photo' ->> 'path', member::text || '/')
        and char_length(payload -> 'photo' ->> 'path') > char_length(member::text || '/')
      )
    );
$$;

create table public.check_ins (
  -- Made by the app, so a check-in saved offline keeps its id when it syncs.
  id uuid primary key,
  member_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- The member's local calendar day the check-in counts for.
  day date not null,
  -- When the member made it, from their phone (it may sync later from offline).
  created_at timestamptz not null default now(),
  -- When the server took it. Set by a trigger; the app can't choose it.
  received_at timestamptz not null default now(),
  kind public.check_in_kind not null,
  payload jsonb not null,
  version smallint not null check (version = 1),
  -- Every time zone is within a day of UTC, so the local day is too.
  constraint check_ins_day_near_created_at check (
    day between (created_at at time zone 'UTC')::date - 1
            and (created_at at time zone 'UTC')::date + 1
  ),
  constraint check_ins_payload_matches_kind check (
    private.check_in_payload_is_valid(kind, payload, member_id)
  )
);

create index check_ins_member_id_day_idx on public.check_ins (member_id, day desc);

-- Whether a photo path is uploaded, and whether a check-in already points at it.
-- Security definer so these see every object and check-in, not just the caller's.
create function private.photo_is_uploaded(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from storage.objects where bucket_id = 'check-in-photos' and name = path
  );
$$;

create function private.photo_is_in_use(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.check_ins where payload -> 'photo' ->> 'path' = path);
$$;

revoke execute on function private.photo_is_uploaded(text) from public;
revoke execute on function private.photo_is_in_use(text) from public;
grant execute on function private.photo_is_uploaded(text) to authenticated;
grant execute on function private.photo_is_in_use(text) to authenticated;

-- Everything a check-in refers to is fixed when it is saved: its times (below), its
-- audience (only in the saving transaction) and its photo (already uploaded, used by
-- no other check-in, and locked in storage while the check-in exists).
--
-- The app picks `created_at` and `day`, so the server bounds them by its own clock:
-- nothing from the future (5 minutes of clock skew allowed) and nothing older than
-- 48 hours, long enough for a check-in saved offline to sync. Without this a member
-- could back-date check-ins or set a far-future day to keep one deletable forever.
create function private.stamp_check_in()
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
  if new.payload ? 'photo' then
    if not private.photo_is_uploaded(new.payload -> 'photo' ->> 'path') then
      raise exception 'upload a check-in''s photo before saving it' using errcode = '23514';
    end if;
    if private.photo_is_in_use(new.payload -> 'photo' ->> 'path') then
      raise exception 'another check-in already uses this photo' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger check_ins_stamp
before insert on public.check_ins
for each row execute function private.stamp_check_in();

-- A check-in's audience: the squads it was sent to (one, some or all of the
-- member's, at most 3), in the order the member picked them.
create table public.check_in_squads (
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  -- A squad a check-in went to can't be deleted: the check-in would lose its audience.
  squad_id uuid not null references public.squads (id) on delete restrict,
  position smallint not null check (position between 1 and 3),
  primary key (check_in_id, squad_id),
  unique (check_in_id, position)
);

create index check_in_squads_squad_id_idx on public.check_in_squads (squad_id);

-- Every check-in goes to at least one squad, from saving it until it is deleted.
-- Checked at commit, so the check-in and its audience can be saved one after the
-- other in the same transaction, and deleting a check-in takes its audience with it.
create function private.require_audience()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  check_in uuid;
begin
  if tg_table_name = 'check_ins' then
    check_in := new.id;
  else
    check_in := old.check_in_id;
  end if;
  if exists (select 1 from public.check_ins where id = check_in)
     and not exists (select 1 from public.check_in_squads where check_in_id = check_in) then
    raise exception 'a check-in goes to at least one squad' using errcode = '23514';
  end if;
  return null;
end;
$$;

create constraint trigger check_ins_have_audience
after insert on public.check_ins
deferrable initially deferred
for each row execute function private.require_audience();

create constraint trigger check_in_squads_keep_audience
after delete or update on public.check_in_squads
deferrable initially deferred
for each row execute function private.require_audience();

-- The caller made the check-in, or is in a squad it was sent to while its author
-- still is too (leaving a squad takes your check-ins out of it).
create function private.can_see_check_in(check_in uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.check_ins c
    where c.id = check_in
      and (
        c.member_id = (select auth.uid())
        or exists (
          select 1
          from public.check_in_squads t
          join public.squad_members viewer
            on viewer.squad_id = t.squad_id and viewer.member_id = (select auth.uid())
          join public.squad_members author
            on author.squad_id = t.squad_id and author.member_id = c.member_id
          where t.check_in_id = c.id
        )
      )
  );
$$;

-- A photo is visible to whoever can see a check-in that points at it.
create function private.can_see_photo(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.check_ins c
    where c.payload -> 'photo' ->> 'path' = path
      and private.can_see_check_in(c.id)
  );
$$;

-- Whether the caller made this check-in, for the policy on check_in_squads.
create function private.owns_check_in(check_in uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.check_ins
    where id = check_in and member_id = (select auth.uid())
  );
$$;

-- Whether the caller made this check-in in the current transaction.
create function private.is_new_own_check_in(check_in uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.check_ins
    where id = check_in and member_id = (select auth.uid()) and received_at = now()
  );
$$;

revoke execute on function private.is_new_own_check_in(uuid) from public;
grant execute on function private.is_new_own_check_in(uuid) to authenticated;
revoke execute on function private.can_see_check_in(uuid) from public;
revoke execute on function private.can_see_photo(text) from public;
revoke execute on function private.owns_check_in(uuid) from public;
grant execute on function private.can_see_check_in(uuid) to authenticated;
grant execute on function private.can_see_photo(text) to authenticated;
grant execute on function private.owns_check_in(uuid) to authenticated;

alter table public.check_ins enable row level security;
alter table public.check_in_squads enable row level security;

create policy "Members see their own check-ins and those sent to their squads"
on public.check_ins for select to authenticated
using (private.can_see_check_in(id));


create policy "Members check in as themselves"
on public.check_ins for insert to authenticated
with check (member_id = (select auth.uid()));

-- Check-ins can't be edited, only deleted on the day they count for. The app holds
-- the exact local day (with its 3am grace); the database allows until that day,
-- plus grace, has ended in the last time zone (UTC-12): 15:00 UTC the next day.
create policy "Members delete their own check-ins on the same day"
on public.check_ins for delete to authenticated
using (
  member_id = (select auth.uid())
  and now() < ((day + 1)::timestamp at time zone 'UTC') + interval '15 hours'
  -- A local day (3am to 3am) lasts at most 25 hours, on the day clocks go back.
  and now() < created_at + interval '25 hours'
);

-- The author sees everywhere a check-in went; others see only their own squads.
create policy "Members see what was sent to their squads"
on public.check_in_squads for select to authenticated
using (private.owns_check_in(check_in_id) or private.is_squad_member(squad_id));

-- Only while saving the check-in: its audience is fixed once it's made. `now()` is
-- the transaction's start, so this matches only a check-in saved in this transaction.
create policy "Members send their own check-ins to squads they are in, when saving them"
on public.check_in_squads for insert to authenticated
with check (
  private.is_new_own_check_in(check_in_id)
  and private.is_squad_member(squad_id)
);

-- The anonymous role gets nothing here; signed-in users get only what the policies allow.
revoke all on public.squads, public.squad_members, public.check_ins, public.check_in_squads from anon;
revoke update on public.check_ins, public.check_in_squads from authenticated;
-- Squads aren't deleted in v1; members leave them.
revoke delete on public.squads from authenticated;

-- The app saves a check-in as its wire JSON (ios/Packages/Contracts), with its
-- audience, in one transaction. Runs as the caller, so every policy above
-- applies.
create function public.create_check_in(check_in jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  payload_key text;
  audience_size int;
begin
  if (check_in ->> 'version') is distinct from '1' then
    raise exception 'unsupported check-in version: %', check_in ->> 'version'
      using errcode = '22023';
  end if;
  if (check_in ->> 'member')::uuid is distinct from auth.uid() then
    raise exception 'a check-in''s member must be the caller' using errcode = '42501';
  end if;
  payload_key := case check_in ->> 'kind'
    when 'trained' then 'training'
    when 'healthyMeal' then 'meal'
    when 'cheatMeal' then 'meal'
    when 'disclaimer' then 'disclaimer'
  end;
  if payload_key is null then
    raise exception 'unknown check-in kind: %', check_in ->> 'kind' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_object_keys(check_in) k
      where k not in ('version', 'id', 'member', 'day', 'createdAt', 'audience', 'kind', payload_key)) > 0
  then
    raise exception 'check-in keys don''t match its kind' using errcode = '22023';
  end if;
  if jsonb_typeof(check_in -> 'audience') is distinct from 'array' then
    raise exception 'a check-in needs its audience' using errcode = '22023';
  end if;
  audience_size := jsonb_array_length(check_in -> 'audience');
  if audience_size not between 1 and 3 then
    raise exception 'a check-in goes to 1 to 3 squads, not %', audience_size using errcode = '22023';
  end if;
  if (select count(distinct value) from jsonb_array_elements_text(check_in -> 'audience')) <> audience_size then
    raise exception 'a check-in''s audience lists each squad once' using errcode = '22023';
  end if;

  insert into public.check_ins (id, member_id, day, created_at, kind, payload, version)
  values (
    (check_in ->> 'id')::uuid,
    (check_in ->> 'member')::uuid,
    (check_in ->> 'day')::date,
    (check_in ->> 'createdAt')::timestamptz,
    (check_in ->> 'kind')::public.check_in_kind,
    check_in -> payload_key,
    1
  );
  insert into public.check_in_squads (check_in_id, squad_id, position)
  select (check_in ->> 'id')::uuid, squad::uuid, position
  from jsonb_array_elements_text(check_in -> 'audience') with ordinality as a (squad, position);
end;
$$;

revoke execute on function public.create_check_in(jsonb) from public, anon;
grant execute on function public.create_check_in(jsonb) to authenticated;

-- Check-ins the caller can see, in the same wire JSON the app sends. `audience` lists
-- only the caller's own squads among those it went to (all of them, for the author).
create view public.check_ins_wire
with (security_invoker = true)
as
select
  c.member_id,
  c.day,
  c.created_at,
  jsonb_build_object(
    'version', c.version,
    'id', c.id,
    'member', c.member_id,
    'day', c.day,
    'createdAt', to_char(c.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'kind', c.kind,
    case c.kind when 'trained' then 'training' when 'disclaimer' then 'disclaimer' else 'meal' end,
    c.payload,
    'audience', coalesce(
      (select jsonb_agg(t.squad_id order by t.position)
       from public.check_in_squads t where t.check_in_id = c.id),
      '[]'::jsonb
    )
  ) as check_in
from public.check_ins c;

revoke all on public.check_ins_wire from anon;
grant select on public.check_ins_wire to authenticated;

-- Check-in photos --------------------------------------------------------------

-- Private bucket. Objects live at "<member id>/<file>", the path a check-in's photo
-- points at. A photo on a saved check-in can't be deleted or replaced until the
-- check-in is deleted. There is no update policy, so nothing is overwritten in place.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'check-in-photos', 'check-in-photos', false, 10485760,
  array['image/jpeg', 'image/heic', 'image/png', 'image/webp']
);

create policy "Members upload photos to their own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'check-in-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not private.photo_is_in_use(name)
);

create policy "Members see their own photos and those on check-ins they can see"
on storage.objects for select to authenticated
using (
  bucket_id = 'check-in-photos'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or private.can_see_photo(name)
  )
);

create policy "Members delete their own photos that no check-in uses"
on storage.objects for delete to authenticated
using (
  bucket_id = 'check-in-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not private.photo_is_in_use(name)
);
