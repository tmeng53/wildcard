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
  updated_at timestamptz not null default now(),
  primary key (member_id, week_start)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.weekly_plans enable row level security;

-- When the member joined: their profile is saved right after their first sign-in. Days of
-- the week before it weren't theirs, so a plan may still change them.
alter table public.profiles add column created_at timestamptz not null default now();
