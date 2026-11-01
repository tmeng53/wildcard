-- The coach's tokens the model's provider had cached (OpenAI caches the beginning of a request it
-- has seen, and charges less for it), counted apart, and their price in the settings, so a wake's
-- cost is what was really charged.

alter table public.coach_usage
  add column cached_input_tokens bigint not null default 0
    check (cached_input_tokens >= 0 and cached_input_tokens <= input_tokens);

-- GPT-6 Luna's cached input: $0.01 per million tokens.
alter table public.coach_settings
  add column cached_input_micros_per_million integer not null default 10000
    check (cached_input_micros_per_million >= 0);

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'rules', rules,
  'inputMicrosPerMillion', input_micros_per_million,
  'cachedInputMicrosPerMillion', cached_input_micros_per_million,
  'outputMicrosPerMillion', output_micros_per_million
)
from public.coach_settings;
