-- What the coach may spend a day (Tracy, 2026-11-08: 「我暂时不收钱，但是 has to be within a reasonable
-- amount per day。太多了，就是说，教练今天下班了。」): a cap per squad, over the squad's own day,
-- and one over everyone's, over New York's day, in US dollars' millionths. A wake that finds its
-- squad (or everyone) over the cap is skipped, not run; the coach is back the next day. Changed
-- with change_coach_settings.

alter table public.coach_settings
  -- $0.10 a squad a day: about ten times a busy squad's day (2026-11-03 to 11-07: under $0.012).
  add column squad_daily_cap_micros integer not null default 100000
    check (squad_daily_cap_micros >= 0),
  -- $5 a day for every squad together, against a bug or abuse.
  add column daily_cap_micros integer not null default 5000000
    check (daily_cap_micros >= 0);

-- A wake skipped because the coach was off duty: done without running, with why in last_error.
alter table public.coach_wakes
  drop constraint coach_wakes_state_check,
  add constraint coach_wakes_state_check
    check (state in ('waiting', 'running', 'done', 'failed', 'skipped'));

-- The day's spending is summed over every squad, by time.
create index coach_usage_by_time on public.coach_usage (at);

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'rules', rules,
  'inputMicrosPerMillion', input_micros_per_million,
  'cachedInputMicrosPerMillion', cached_input_micros_per_million,
  'outputMicrosPerMillion', output_micros_per_million,
  'noteHour', note_hour,
  'holidays', holidays -> 'days',
  'squadDailyCapMicros', squad_daily_cap_micros,
  'dailyCapMicros', daily_cap_micros
)
from public.coach_settings;
