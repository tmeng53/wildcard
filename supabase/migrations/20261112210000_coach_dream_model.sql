-- The night's dream rewrites each squad's memory, which every later wake goes on, so it gets its
-- own model and reasoning (Tracy, 2026-11-12: 用稍微好一点的模型). It starts on the day's model,
-- thinking hard; an admin moves it to another priced model through the admin tools.

alter table public.coach_settings
  add column dream_model text
    constraint coach_settings_dream_model check (dream_model ~ '^openai/[A-Za-z0-9._:-]{1,100}$'),
  add column dream_reasoning text not null default 'high'
    constraint coach_settings_dream_reasoning
      check (dream_reasoning in ('none', 'minimal', 'low', 'medium', 'high'));

update public.coach_settings set dream_model = model;

alter table public.coach_settings alter column dream_model set not null;

-- The coach settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'reasoning', reasoning,
  'dreamModel', dream_model,
  'dreamReasoning', dream_reasoning,
  'rules', rules,
  'wakes', wakes,
  'noteHour', note_hour,
  'holidays', holidays -> 'days'
)
from public.coach_settings;
