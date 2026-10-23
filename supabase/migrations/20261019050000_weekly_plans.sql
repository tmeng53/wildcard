-- Members' weekly plans: which days of a week they train and which they rest. 本周 counts
-- against the plan's training days. A week without a plan of its own follows the member's
-- latest earlier one, so a row is written only when the member changes their plan. Every
-- rule (rest days fixed once the week starts, past days and weeks read-only) lives in the
-- API's check-ins module; the database keeps keys and shapes only.

create table public.weekly_plans (
  member_id uuid not null references auth.users (id) on delete cascade,
  -- The week's Monday, in the member's own calendar.
  week_start date not null check (extract(isodow from week_start) = 1),
  -- The seven days, Monday first, as stored JSON with its shape's version at the top:
  -- {"version": 1, "days": [...]}. The API owns the shape and parses it on every read.
  payload jsonb not null check (coalesce(jsonb_typeof(payload -> 'version') = 'number', false)),
  primary key (member_id, week_start)
);

-- Every saved change to a week's plan, oldest first, with the whole plan as saved: replaying
-- it rebuilds what any week's plan was on any day. Written in the same statement as the
-- change, and only when the plan changed. Only grows (public.member_log_append_only);
-- deleting the account takes it.
create table public.weekly_plan_events (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null,
  payload jsonb not null,
  at timestamptz not null default now()
);

create index weekly_plan_events_member_id_idx on public.weekly_plan_events (member_id);

create trigger weekly_plan_events_append_only
  before update or delete on public.weekly_plan_events
  for each row execute function public.member_log_append_only();

create trigger weekly_plan_events_no_truncate
  before truncate on public.weekly_plan_events
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.weekly_plans enable row level security;
alter table public.weekly_plan_events enable row level security;

-- Members' 饮食小目标: up to 3 eating habits for a week (never a body number, a calorie or a
-- macro), each one of the app's suggestions or the member's own words. A row only for a week the
-- member set them for; unlike the plan, goals don't carry over. Which goals are allowed, and that
-- only a week that hasn't started can change, is the API's to decide.
create table public.fuel_goals (
  member_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  -- {"version": 1, "goals": [...]}: the API owns the shape and parses it on every read.
  payload jsonb not null check (coalesce(jsonb_typeof(payload -> 'version') = 'number', false)),
  primary key (member_id, week_start)
);

-- Every saved change to a week's 饮食小目标, oldest first, with the goals as saved. Written in the
-- same statement as the change, and only when the goals changed. Only grows
-- (public.member_log_append_only); deleting the account takes it.
create table public.fuel_goal_events (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null,
  payload jsonb not null,
  at timestamptz not null default now()
);

create index fuel_goal_events_member_id_idx on public.fuel_goal_events (member_id);

create trigger fuel_goal_events_append_only
  before update or delete on public.fuel_goal_events
  for each row execute function public.member_log_append_only();

create trigger fuel_goal_events_no_truncate
  before truncate on public.fuel_goal_events
  for each statement execute function public.member_log_append_only();

alter table public.fuel_goals enable row level security;
alter table public.fuel_goal_events enable row level security;
