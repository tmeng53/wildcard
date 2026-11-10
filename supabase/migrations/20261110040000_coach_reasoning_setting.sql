-- How hard the coach's model thinks before it answers (Tracy, 2026-11-10: low, to read a
-- member's tone instead of defending its own line). Thinking is billed as output tokens, which
-- coach_usage already counts. Changed through the admin tools like the rest of the settings.

alter table public.coach_settings
  add column reasoning text not null default 'low'
    constraint coach_settings_reasoning check (reasoning in ('none', 'minimal', 'low', 'medium', 'high'));

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'reasoning', reasoning,
  'rules', rules,
  'wakes', wakes,
  'inputMicrosPerMillion', input_micros_per_million,
  'cachedInputMicrosPerMillion', cached_input_micros_per_million,
  'outputMicrosPerMillion', output_micros_per_million,
  'noteHour', note_hour,
  'holidays', holidays -> 'days',
  'squadDailyCapMicros', squad_daily_cap_micros,
  'dailyCapMicros', daily_cap_micros
)
from public.coach_settings;
