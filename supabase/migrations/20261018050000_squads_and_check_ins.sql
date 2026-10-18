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
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (squad_id, member_id)
);

create index squad_members_member_id_idx on public.squad_members (member_id);

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

create policy "The creator deletes the squad"
on public.squads for delete to authenticated
using (created_by = (select auth.uid()));

create policy "Members see who is in their squads"
on public.squad_members for select to authenticated
using ((select private.is_squad_member(squad_id)));

create policy "Members leave squads"
on public.squad_members for delete to authenticated
using (member_id = (select auth.uid()));

-- Check-ins --------------------------------------------------------------------

create type public.check_in_kind as enum ('trained', 'ateClean', 'disclaimer');

-- The kind-specific object from the wire JSON (`training`, `meal` or `disclaimer`),
-- checked against the same rules as the Swift contract. The app enforces the exact
-- 40-character 免责声明 limit in characters people see; Postgres counts code points,
-- so it holds a looser cap that an emoji sequence can't trip.
create function private.check_in_payload_is_valid(
  kind public.check_in_kind, payload jsonb, member uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(payload) = 'object'
    and case kind
      when 'trained' then
        payload ?& array['sport', 'minutes']
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('sport', 'minutes', 'photo')) = 0
        and payload ->> 'sport' in (
          'run', 'strength', 'yoga', 'pilates', 'swim', 'cycle',
          'ball', 'climb', 'hike', 'dance', 'other'
        )
        and jsonb_typeof(payload -> 'minutes') = 'number'
        and (payload ->> 'minutes') ~ '^[0-9]+$'
        and (payload ->> 'minutes')::int between 1 and 600
      when 'ateClean' then
        payload ? 'slot'
        and (select count(*) from jsonb_object_keys(payload) k
             where k not in ('slot', 'photo')) = 0
        and payload ->> 'slot' in ('breakfast', 'lunch', 'dinner', 'snack')
      when 'disclaimer' then
        payload ? 'text'
        and (select count(*) from jsonb_object_keys(payload) k where k <> 'text') = 0
        and jsonb_typeof(payload -> 'text') = 'string'
        and char_length(btrim(payload ->> 'text')) between 1 and 160
        and payload ->> 'text' = btrim(payload ->> 'text')
    end
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
  created_at timestamptz not null default now(),
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

-- The squads a check-in was sent to. The app sends to one squad or to all of them.
create table public.check_in_squads (
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  squad_id uuid not null references public.squads (id) on delete cascade,
  primary key (check_in_id, squad_id)
);

create index check_in_squads_squad_id_idx on public.check_in_squads (squad_id);

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

create policy "Members edit their own check-ins"
on public.check_ins for update to authenticated
using (member_id = (select auth.uid()))
with check (member_id = (select auth.uid()));

create policy "Members delete their own check-ins"
on public.check_ins for delete to authenticated
using (member_id = (select auth.uid()));

-- The author sees everywhere a check-in went; others see only their own squads.
create policy "Members see what was sent to their squads"
on public.check_in_squads for select to authenticated
using (private.owns_check_in(check_in_id) or private.is_squad_member(squad_id));

create policy "Members send their own check-ins to squads they are in"
on public.check_in_squads for insert to authenticated
with check (
  (select private.owns_check_in(check_in_id))
  and (select private.is_squad_member(squad_id))
);

create policy "Members take their own check-ins back from a squad"
on public.check_in_squads for delete to authenticated
using ((select private.owns_check_in(check_in_id)));

-- The anonymous role gets nothing here; signed-in users get only what the policies allow.
revoke all on public.squads, public.squad_members, public.check_ins, public.check_in_squads from anon;

-- Check-in photos --------------------------------------------------------------

-- Private bucket. Objects live at "<member id>/<file>", the path a check-in's photo points at.
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

create policy "Members delete their own photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'check-in-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
