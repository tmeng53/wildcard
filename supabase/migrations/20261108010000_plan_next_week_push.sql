-- 去安排下周 (Tracy, 2026-11-08): every Sunday evening on each member's own clock, one push
-- asking them to plan next week's 出赛表, sent to everyone whether or not they have planned it.
-- Its switch and time sit with the daily push's settings, so both change without a deploy
-- through the same admin tool and log; each member's own daily push switch still applies.
alter table public.daily_push_settings
  add column plan_reminder_sending boolean not null default true,
  add column plan_reminder_hour integer not null default 20
    check (plan_reminder_hour between 0 and 23),
  add column plan_reminder_minute integer not null default 30
    check (plan_reminder_minute between 0 and 59);

-- The log gets the whole new value, as every change writes it.
insert into public.daily_push_setting_events (settings)
select jsonb_build_object(
  'version', 2,
  'sending', sending,
  'hour', hour,
  'planReminderSending', plan_reminder_sending,
  'planReminderHour', plan_reminder_hour,
  'planReminderMinute', plan_reminder_minute
)
from public.daily_push_settings;

-- One row per member per week the reminder asked them to plan (that week's Monday), claimed
-- before it is sent, so two runs at once or a run repeated never send it twice. Deleting the
-- account takes its rows.
create table public.plan_reminder_pushes (
  member_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  handled_at timestamptz not null default now(),
  primary key (member_id, week_start)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.plan_reminder_pushes enable row level security;
