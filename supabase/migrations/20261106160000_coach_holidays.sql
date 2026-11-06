-- The coach's holiday calendar (Tracy, 2026-11-06: 「能不能给他一个 holiday calendar」, 「还有很多我们
-- 没做主题的 holiday」): each day's name the coach is told in every wake's task, as a plain fact,
-- never how to say it. A date is `MM-DD` for every year or `YYYY-MM-DD` for one year only (a
-- holiday that moves, such as 春节 or Thanksgiving). Changed with change_coach_settings. Stored
-- JSON, so it carries its own `version`: `{ "version": 1, "days": [{ "date", "name" }] }`.

alter table public.coach_settings
  add column holidays jsonb not null default '{"version": 1, "days": []}'::jsonb
    check (
      (holidays ->> 'version') = '1'
      and jsonb_typeof(holidays -> 'days') = 'array'
      and jsonb_array_length(holidays -> 'days') <= 500
    );

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
  'holidays', holidays -> 'days'
)
from public.coach_settings;
