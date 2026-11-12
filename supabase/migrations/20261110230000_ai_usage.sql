-- One ledger for every language-model call (Tracy, 2026-11-10: 「所有我们只要 call LLM，一定要
-- backtrack to user and group」), and one daily budget a squad's calls all count toward: the
-- coach's wakes and letters, 请假条 drafts and the weekly awards alike. Until now only the coach
-- logged its calls (coach_usage, by squad) and only the coach had a budget; drafts had a count of
-- batches a member a day instead (disclaimer_draft_requests), which goes.

-- Every call: what it was for, the member it was for or who asked (none for a call for the whole
-- squad), the squad whose budget pays (none for a member without a squad), the model, its tokens
-- and their cost at the price of the time, in US dollars' millionths. A call that failed counts
-- what it spent. Kept with the squad, which takes them when it ends; a deleted account leaves its
-- calls to its squad, without its id.
create table public.ai_usage (
  id bigint generated always as identity primary key,
  feature text not null
    check (feature in ('coach-wake', 'coach-letter', 'coach-preview', 'disclaimer-drafts', 'weekly-awards')),
  squad_id uuid references public.squads (id) on delete cascade,
  member_id uuid references auth.users (id) on delete set null,
  model text not null check (model ~ '^(openai|anthropic)/[A-Za-z0-9._:-]{1,100}$'),
  requests integer not null check (requests >= 0),
  input_tokens bigint not null check (input_tokens >= 0),
  cached_input_tokens bigint not null check (cached_input_tokens >= 0 and cached_input_tokens <= input_tokens),
  output_tokens bigint not null check (output_tokens >= 0),
  cost_micros bigint not null check (cost_micros >= 0),
  at timestamptz not null default now()
);

create index ai_usage_by_squad on public.ai_usage (squad_id, at);
create index ai_usage_by_member on public.ai_usage (member_id, at);
create index ai_usage_by_time on public.ai_usage (at);

-- A log: a row is never changed or removed, except by the cascade of a squad's end, and a deleted
-- account's id leaving it.
create function public.ai_usage_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception '% is append-only', tg_table_name using errcode = '42501';
  end if;
  if tg_op = 'DELETE' and old.squad_id is not null
    and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE' and old.member_id is not null and new.member_id is null
    and (to_jsonb(new) - 'member_id') = (to_jsonb(old) - 'member_id')
    and not exists (select 1 from auth.users where id = old.member_id) then
    return new;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger ai_usage_append_only
  before update or delete on public.ai_usage
  for each row execute function public.ai_usage_append_only();
create trigger ai_usage_no_truncate
  before truncate on public.ai_usage
  for each statement execute function public.ai_usage_append_only();

alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

-- The coach's calls so far, each to its squad: a run with a wake was a wake's; one without, a
-- letter's or an admin's preview, which the old log didn't tell apart (counted as letters).
insert into public.ai_usage
  (feature, squad_id, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros, at)
select
  case when wake_id is null then 'coach-letter' else 'coach-wake' end,
  squad_id,
  case when model like '%/%' then model else 'openai/' || model end,
  requests, input_tokens, cached_input_tokens, output_tokens, cost_micros, at
from public.coach_usage
order by id;

drop table public.coach_usage;

-- What the calls cost and how much a day may go on them: each model's prices, the cap per squad
-- (over the squad's own day) and the cap for every squad together (over New York's day). Moved
-- from the coach's settings, since every call counts now. Changed with change_ai_usage_settings.
create table public.ai_usage_settings (
  only_row boolean primary key default true check (only_row),
  -- {"version": 1, "models": {"openai/gpt-6-luna": {"inputMicrosPerMillion": …, …}}}
  prices jsonb not null check (coalesce(jsonb_typeof(prices -> 'version') = 'number', false)),
  squad_daily_cap_micros integer not null check (squad_daily_cap_micros >= 0),
  daily_cap_micros integer not null check (daily_cap_micros >= 0)
);

create table public.ai_usage_setting_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "prices": ..., ...}.
  settings jsonb not null check (coalesce(jsonb_typeof(settings -> 'version') = 'number', false))
);

create trigger ai_usage_settings_kept
  before delete on public.ai_usage_settings
  for each row execute function public.settings_row_kept();
create trigger ai_usage_settings_no_truncate
  before truncate on public.ai_usage_settings
  for each statement execute function public.settings_row_kept();
create trigger ai_usage_setting_events_append_only
  before update or delete on public.ai_usage_setting_events
  for each row execute function public.settings_log_append_only();
create trigger ai_usage_setting_events_no_truncate
  before truncate on public.ai_usage_setting_events
  for each statement execute function public.settings_log_append_only();

alter table public.ai_usage_settings enable row level security;
alter table public.ai_usage_setting_events enable row level security;
revoke all on public.ai_usage_settings, public.ai_usage_setting_events from anon, authenticated;

-- Every model a setting names now is priced as the coach's was (all of them GPT-6 Luna on the
-- hosted project), and the caps are the coach's. A call to a model with no price isn't made.
insert into public.ai_usage_settings (prices, squad_daily_cap_micros, daily_cap_micros)
select
  jsonb_build_object(
    'version', 1,
    'models', (
      select jsonb_object_agg(name, jsonb_build_object(
        'inputMicrosPerMillion', c.input_micros_per_million,
        'cachedInputMicrosPerMillion', c.cached_input_micros_per_million,
        'outputMicrosPerMillion', c.output_micros_per_million
      ))
      from (
        select c.model as name
        union select model from public.disclaimer_draft_settings
        union select model from public.weekly_award_settings
      ) as models
    )
  ),
  c.squad_daily_cap_micros,
  c.daily_cap_micros
from public.coach_settings as c;

insert into public.ai_usage_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'prices', prices -> 'models',
  'squadDailyCapMicros', squad_daily_cap_micros,
  'dailyCapMicros', daily_cap_micros
)
from public.ai_usage_settings;

alter table public.coach_settings
  drop column input_micros_per_million,
  drop column cached_input_micros_per_million,
  drop column output_micros_per_million,
  drop column squad_daily_cap_micros,
  drop column daily_cap_micros;

-- The coach settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'reasoning', reasoning,
  'rules', rules,
  'wakes', wakes,
  'noteHour', note_hour,
  'holidays', holidays -> 'days'
)
from public.coach_settings;

-- 请假条 drafts count toward their squad's budget now, not a member's batches a day.
drop table public.disclaimer_draft_requests;

alter table public.disclaimer_draft_settings drop column batches_per_day;

insert into public.disclaimer_draft_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'writing', writing,
  'model', model,
  'instructions', instructions,
  'memeChance', meme_chance
)
from public.disclaimer_draft_settings;
