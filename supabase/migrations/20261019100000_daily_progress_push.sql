-- The once-a-day progress push (at 6pm in each member's own time zone) and the switches that
-- turn each kind of push off.
-- As with every table, only our API reads and writes these.

-- Push settings ------------------------------------------------------------------------

-- A row only for a switch the member changed: no row means the push is on. Which kinds of
-- push exist is the API's to decide, so `topic` is text it checks, not an enum a migration
-- would have to change.
create table public.push_settings (
  member_id uuid not null references auth.users (id) on delete cascade,
  topic text not null,
  enabled boolean not null,
  primary key (member_id, topic)
);

-- Every switch a member flipped, oldest first, with where it was left. Written in the same
-- statement as the change, and only when the switch changed. Only grows
-- (public.member_log_append_only); deleting the account takes it.
create table public.push_setting_events (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  topic text not null,
  enabled boolean not null,
  at timestamptz not null default now()
);

create index push_setting_events_member_id_idx on public.push_setting_events (member_id);

create trigger push_setting_events_append_only
  before update or delete on public.push_setting_events
  for each row execute function public.member_log_append_only();

create trigger push_setting_events_no_truncate
  before truncate on public.push_setting_events
  for each statement execute function public.member_log_append_only();

-- Daily pushes ---------------------------------------------------------------------------

-- One row per member per local day the daily push was handled, claimed before it is sent, so
-- two runs at once or a run repeated never send it twice. `quiet` is true when there was
-- nothing to say that day, so nothing was sent.
create table public.daily_pushes (
  member_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  quiet boolean not null,
  handled_at timestamptz not null default now(),
  primary key (member_id, day)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.push_settings enable row level security;
alter table public.push_setting_events enable row level security;
alter table public.daily_pushes enable row level security;
