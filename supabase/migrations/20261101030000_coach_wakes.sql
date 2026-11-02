-- The AI coach at work (the coach module): the coach each squad hires, the wakes it is woken for,
-- each squad's memory files, the 战术板 line it posts each day, and the tokens every wake used,
-- counted per squad so coaching can later be paid for by usage. Nothing here reaches the app
-- yet, and nothing runs while coaching is off.

-- Squads hire their coach: a squad is coached while it has one hired (and coaching is on), so
-- the trial list of squads in the settings goes.
alter table public.coach_settings drop column only_squads;

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'rules', rules,
  'inputMicrosPerMillion', input_micros_per_million,
  'outputMicrosPerMillion', output_micros_per_million
)
from public.coach_settings;

-- The coach each squad has hired now: one at a time. Firing it removes the row; the squad's
-- memory stays with the squad for whichever coach it hires next.
create table public.squad_coaches (
  squad_id uuid primary key references public.squads (id) on delete cascade,
  coach_id text not null references public.coaches (id),
  hired_by uuid references auth.users (id) on delete set null,
  hired_at timestamptz not null default now()
);

-- Every hire and every firing, with who did it.
create table public.squad_coach_events (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  kind text not null check (kind in ('hired', 'fired')),
  coach_id text not null references public.coaches (id),
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now()
);

create index squad_coach_events_by_squad on public.squad_coach_events (squad_id, id);

-- Each time a coach is woken for a squad: for a check-in, or once a day for the 战术板 line.
-- A queue the coach job works through: each wake is claimed, run, and marked done or failed.
-- It is work, not history; what a wake changed is in the files, notes and usage below.
create table public.coach_wakes (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  reason text not null check (reason in ('checkIn', 'daily')),
  -- The check-in a `checkIn` wake is for; the check-in's deletion takes its wake.
  check_in_id uuid references public.check_ins (id) on delete cascade,
  -- The day (New York) a `daily` wake is for.
  day date,
  check ((reason = 'checkIn') = (check_in_id is not null)),
  check ((reason = 'daily') = (day is not null)),
  state text not null default 'waiting' check (state in ('waiting', 'running', 'done', 'failed')),
  -- Tries so far: a wake that failed is tried again until its third try.
  tries integer not null default 0 check (tries between 0 and 3),
  claimed_at timestamptz,
  -- Why the last try failed, for the admins; never shown to members.
  last_error text check (char_length(last_error) <= 1000),
  created_at timestamptz not null default now()
);

create unique index coach_wakes_one_per_check_in on public.coach_wakes (squad_id, check_in_id)
  where reason = 'checkIn';
create unique index coach_wakes_one_a_day on public.coach_wakes (squad_id, day)
  where reason = 'daily';
create index coach_wakes_to_run on public.coach_wakes (created_at)
  where state in ('waiting', 'running');
-- A squad's wakes run one after another, each reading what the last one wrote.
create unique index coach_wakes_one_running on public.coach_wakes (squad_id)
  where state = 'running';

-- Each squad's memory: the files its coach keeps (squad.md, memory.md, a page per member), a
-- new row for every version, so the newest of a path is the file now and the rest is its
-- history. `people/<member id>.md`, and members named in a body as `{队员:<member id>}`; the
-- model sees each member as 队员N instead, numbered as the squad is now. The squad's
-- end takes its files; a member's page goes with their account.
create table public.coach_files (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  path text not null check (
    path in ('squad.md', 'memory.md')
    or path ~ '^people/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.md$'
  ),
  -- The member a `people/` page is about, so their account's deletion takes it.
  member_id uuid references auth.users (id) on delete cascade,
  check ((path like 'people/%') = (member_id is not null)),
  check (member_id is null or path = 'people/' || member_id || '.md'),
  -- The model's limit is 8000 characters as it reads them; stored, each member it names (队员N)
  -- is their id (`{队员:<id>}`), which is longer, so the cap here allows a file of nothing but names.
  body text not null check (char_length(body) <= 120000),
  wake_id bigint references public.coach_wakes (id) on delete set null,
  at timestamptz not null default now()
);

create index coach_files_newest on public.coach_files (squad_id, path, id desc);

-- The coach's 战术板 line: at most one a squad a day.
create table public.coach_notes (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  coach_id text not null references public.coaches (id),
  day date not null,
  text text not null check (char_length(text) between 1 and 60),
  wake_id bigint references public.coach_wakes (id) on delete set null,
  at timestamptz not null default now(),
  unique (squad_id, day)
);

-- What each wake used, per squad: the model's requests and tokens, and their cost at the
-- price in the settings at the time, in US dollars' millionths. A failed wake's tokens count
-- too. Kept with the squad, which takes them when it ends.
create table public.coach_usage (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  wake_id bigint references public.coach_wakes (id) on delete set null,
  coach_id text not null references public.coaches (id),
  model text not null,
  requests integer not null check (requests >= 0),
  input_tokens bigint not null check (input_tokens >= 0),
  output_tokens bigint not null check (output_tokens >= 0),
  cost_micros bigint not null check (cost_micros >= 0),
  at timestamptz not null default now()
);

create index coach_usage_by_squad on public.coach_usage (squad_id, at);

-- Files, notes, usage and hires are logs: a row is never changed or removed, except by the cascade
-- of a squad's end or an account's deletion (the wake a row points to may go, too).
create function public.coach_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  -- A member's page (only coach_files has `member_id`) goes with the member.
  if tg_op = 'DELETE' and to_jsonb(old) ->> 'member_id' is not null
    and not exists (select 1 from auth.users where id = (to_jsonb(old) ->> 'member_id')::uuid) then
    return old;
  end if;
  -- The wake a row points to may go (its check-in did), and the reference with it; and a
  -- deleted account's id leaves the log's `changed_by`. Nothing else ever changes.
  if tg_op = 'UPDATE' and (
    (to_jsonb(old) ->> 'wake_id' is not null and to_jsonb(new) ->> 'wake_id' is null
      and (to_jsonb(new) - 'wake_id') = (to_jsonb(old) - 'wake_id')
      and not exists (select 1 from public.coach_wakes where id = (to_jsonb(old) ->> 'wake_id')::bigint))
    or (to_jsonb(old) ->> 'changed_by' is not null and to_jsonb(new) ->> 'changed_by' is null
      and (to_jsonb(new) - 'changed_by') = (to_jsonb(old) - 'changed_by')
      and not exists (select 1 from auth.users where id = (to_jsonb(old) ->> 'changed_by')::uuid))
  ) then
    return new;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger coach_files_append_only
  before update or delete on public.coach_files
  for each row execute function public.coach_log_append_only();
create trigger coach_files_no_truncate
  before truncate on public.coach_files
  for each statement execute function public.settings_log_append_only();
create trigger coach_notes_append_only
  before update or delete on public.coach_notes
  for each row execute function public.coach_log_append_only();
create trigger coach_notes_no_truncate
  before truncate on public.coach_notes
  for each statement execute function public.settings_log_append_only();
create trigger coach_usage_append_only
  before update or delete on public.coach_usage
  for each row execute function public.coach_log_append_only();
create trigger coach_usage_no_truncate
  before truncate on public.coach_usage
  for each statement execute function public.settings_log_append_only();
create trigger squad_coach_events_append_only
  before update or delete on public.squad_coach_events
  for each row execute function public.coach_log_append_only();
create trigger squad_coach_events_no_truncate
  before truncate on public.squad_coach_events
  for each statement execute function public.settings_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_wakes enable row level security;
alter table public.coach_files enable row level security;
alter table public.coach_notes enable row level security;
alter table public.coach_usage enable row level security;
alter table public.squad_coaches enable row level security;
alter table public.squad_coach_events enable row level security;
