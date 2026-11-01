-- Members' typical week (每周模板): the plan every week starts from. A week without a plan saved
-- for it follows the member's template, never an earlier week, so a change to one week stays in
-- that week. The member makes it at sign-up and changes it in the app; before that a week follows
-- the API's default. The shape and every rule live in the API's check-ins module.
--
-- The table is its own log: one row per change, with the week it applies from, never updated or
-- deleted. A week follows the latest row applying from it or before, so changing the template
-- changes the weeks to come and never one that has begun or is over.

create table public.plan_templates (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- The first week this template is for: the week the member made it in at sign-up, else the
  -- week after the change.
  from_week date not null check (extract(isodow from from_week) = 1),
  -- The seven days, Monday first: {"version": 1, "days": [...]}, as in weekly_plans.
  payload jsonb not null check (coalesce(jsonb_typeof(payload -> 'version') = 'number', false)),
  at timestamptz not null default now()
);

create index plan_templates_member_id_from_week_idx on public.plan_templates (member_id, from_week);

create trigger plan_templates_append_only
  before update or delete on public.plan_templates
  for each row execute function public.member_log_append_only();

create trigger plan_templates_no_truncate
  before truncate on public.plan_templates
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.plan_templates enable row level security;

-- Until now a week without a plan of its own followed the member's latest earlier one. Each
-- saved week becomes a template from that week on, so every week keeps the plan it had.
insert into public.plan_templates (member_id, from_week, payload)
select member_id, week_start, payload
from public.weekly_plans
order by member_id, week_start;
