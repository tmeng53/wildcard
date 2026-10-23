-- What squadmates see of a member besides their check-ins. Every rule about these values
-- (lengths, ids, swatches) is the API's, like every other rule; the database keeps only
-- what keeps the rows whole.

-- The catchphrase (口头禅): what their character shouts when the squad cheers a teammate's
-- 练了. Null until they pick one, and the app then uses their persona's own line.
alter table public.profiles add column catchphrase text;

-- Their character, made together in the character editor right after signing in: the
-- nickname squadmates call them, and the look (persona, a variant per slot, swatches) as
-- JSON with a top-level numeric version. Both null until then, never one without the other.
alter table public.profiles
  add column nickname text,
  add column look jsonb,
  add constraint profiles_character_whole check ((nickname is null) = (look is null)),
  add constraint profiles_look_versioned check (
    look is null or coalesce(jsonb_typeof(look -> 'version') = 'number', false)
  );

-- Every saved change to a profile, oldest first: the whole profile as it stood after the
-- change, so replaying the log rebuilds any past look, nickname, 口头禅 or time zone. Written
-- in the same statement as the change, and only when something changed. Only grows
-- (public.member_log_append_only); deleting the account takes it.
create table public.profile_events (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  time_zone text not null,
  catchphrase text,
  nickname text,
  look jsonb,
  at timestamptz not null default now()
);

create index profile_events_member_id_idx on public.profile_events (member_id);

create trigger profile_events_append_only
  before update or delete on public.profile_events
  for each row execute function public.member_log_append_only();

create trigger profile_events_no_truncate
  before truncate on public.profile_events
  for each statement execute function public.member_log_append_only();

alter table public.profile_events enable row level security;
