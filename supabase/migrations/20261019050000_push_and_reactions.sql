-- Reactions on check-ins (a teammate's kudos, left in the app) and the phones each member
-- gets push notifications on.
-- As with every table, only our API reads and writes these; the database keeps what must
-- stay true however they are written.

-- Reactions --------------------------------------------------------------------------

-- At most one reaction per member per check-in, as with Strava's kudos: reacting again
-- replaces it. Which reactions exist is the API's to decide, so `kind` is text it checks,
-- not an enum a migration would have to change.
create table public.check_in_reactions (
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  reacted_at timestamptz not null,
  primary key (check_in_id, member_id)
);

-- Push devices -----------------------------------------------------------------------

-- An APNs device token names one app install on one phone. It is the key, so when someone
-- else signs in on that phone, registering it again moves it to them.
create table public.push_devices (
  token text primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- Which APNs servers the token belongs to: a build from Xcode gets sandbox tokens,
  -- TestFlight and the App Store get production ones.
  environment text not null check (environment in ('sandbox', 'production')),
  registered_at timestamptz not null default now()
);

create index push_devices_member_id_idx on public.push_devices (member_id);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.check_in_reactions enable row level security;
alter table public.push_devices enable row level security;
