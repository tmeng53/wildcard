-- The teammate push: a squadmate's 训练 told to the rest of the squad as it is posted
-- (「小美刚练完网球 62 分钟」), ringing for the first few a day and silent after. Owned by the
-- push module; as with every table, only our API reads and writes it.

-- Which pushes an install can show. A push carries a key in the app's String Catalog, and a
-- build from before a key was added has no words for it, so each phone says which generation of
-- pushes its build knows and a push goes only to phones that know it. 1: every push from before
-- generations; 2 adds the teammate push.
alter table public.push_devices
  add column push_generation smallint not null default 1 check (push_generation >= 1);

-- The teammate push for everyone, kept in the database so it changes without a deploy: whether
-- it goes out at all, and how many may ring on one member's phone in 24 hours (the rest of that
-- day's arrive silently). One row, changed only through the admin tools. Each member's own
-- switch (push_settings) still applies on top.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the other settings are (settings_log_append_only()).
create table public.teammate_push_settings (
  only_row boolean primary key default true check (only_row),
  sending boolean not null,
  daily_rings integer not null check (daily_rings between 0 and 50)
);

create table public.teammate_push_setting_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "sending": ..., "dailyRings": ...}.
  settings jsonb not null check (coalesce(jsonb_typeof(settings -> 'version') = 'number', false))
);

create trigger teammate_push_setting_events_append_only
  before update or delete on public.teammate_push_setting_events
  for each row execute function public.settings_log_append_only();

create trigger teammate_push_setting_events_no_truncate
  before truncate on public.teammate_push_setting_events
  for each statement execute function public.settings_log_append_only();

create trigger teammate_push_settings_kept
  before delete on public.teammate_push_settings
  for each row execute function public.settings_row_kept();

create trigger teammate_push_settings_no_truncate
  before truncate on public.teammate_push_settings
  for each statement execute function public.settings_row_kept();

-- The first values: on, and up to 5 ring in 24 hours.
with first as (
  insert into public.teammate_push_settings (sending, daily_rings) values (true, 5)
  returning *
)
insert into public.teammate_push_setting_events (settings)
select jsonb_build_object('version', 1, 'sending', sending, 'dailyRings', daily_rings) from first;

-- Each teammate push handled: one row per check-in and member told of it, claimed before
-- sending, so an event delivered twice pushes once, and `rang` rows count against the member's
-- rings. `check_in_id` is the check-in's id, kept without a reference: a deleted post keeps the
-- record that its push was sent. Never changed, so it is its own log; only the account's
-- deletion removes a member's rows.
create table public.teammate_pushes (
  check_in_id uuid not null,
  member_id uuid not null references auth.users (id) on delete cascade,
  rang boolean not null,
  at timestamptz not null,
  primary key (check_in_id, member_id)
);

create index teammate_pushes_member_id_at_idx on public.teammate_pushes (member_id, at) where rang;

create trigger teammate_pushes_append_only
  before update or delete on public.teammate_pushes
  for each row execute function public.member_log_append_only();

create trigger teammate_pushes_no_truncate
  before truncate on public.teammate_pushes
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.teammate_push_settings enable row level security;
alter table public.teammate_push_setting_events enable row level security;
alter table public.teammate_pushes enable row level security;
