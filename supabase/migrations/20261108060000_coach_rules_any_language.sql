-- The coach writes in the language each wake's task names (the reader's app language, or the
-- squad's for what the whole squad reads), so the shared rules no longer say Chinese only
-- (Tracy, 2026-11-08). Only a rules text that still has the old line changes; the hosted
-- settings were already changed with change_coach_settings, so nothing is logged there.

with changed as (
  update public.coach_settings
  set rules = regexp_replace(rules, '^- 只说中文[^\n]*$', '- 用任务说的语言写；队员写的别种语言的词原样保留。', 'n')
  where rules ~ '(^|\n)- 只说中文'
  returning *
)
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
from changed;
