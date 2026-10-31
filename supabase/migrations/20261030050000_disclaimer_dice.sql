-- The 请假条 dice: ready-made lines the app rolls when the AI can't write (offline, drafts off,
-- or no consent), kept in the database so they change without an app release. One row, owned by
-- the disclaimer drafts module, changed only through the admin tools; the public catalog serves
-- it, and the app keeps the last copy it read (and ships one).
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the other settings are (settings_log_append_only()).
create table public.disclaimer_dice (
  only_row boolean primary key default true check (only_row),
  -- Each line in every language the app speaks: [{"zhHans": ..., "en": ..., "zhHant": ...}].
  lines jsonb not null check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) > 0)
);

create table public.disclaimer_dice_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "lines": [...]}.
  dice jsonb not null check (coalesce(jsonb_typeof(dice -> 'version') = 'number', false))
);

create trigger disclaimer_dice_events_append_only
  before update or delete on public.disclaimer_dice_events
  for each row execute function public.settings_log_append_only();

create trigger disclaimer_dice_events_no_truncate
  before truncate on public.disclaimer_dice_events
  for each statement execute function public.settings_log_append_only();

create trigger disclaimer_dice_kept
  before delete on public.disclaimer_dice
  for each row execute function public.settings_row_kept();

create trigger disclaimer_dice_no_truncate
  before truncate on public.disclaimer_dice
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.disclaimer_dice enable row level security;
alter table public.disclaimer_dice_events enable row level security;

-- The first lines: the ones the app shipped with.
with first as (
  insert into public.disclaimer_dice (lines) values ('[
    {"zhHans": "昨天的腿还没回来", "en": "My legs haven''t come back from yesterday", "zhHant": "昨天的腿還沒回來"},
    {"zhHans": "加班到十点，算脑力训练", "en": "Worked till ten: brain training", "zhHant": "加班到十點，算腦力訓練"},
    {"zhHans": "下雨，场地条件不允许", "en": "Rain. Field conditions say no", "zhHant": "下雨，場地條件不允許"},
    {"zhHans": "在 Costco 走了两小时，算有氧", "en": "Two hours walking Costco. That''s cardio", "zhHant": "在 Costco 走了兩小時，算有氧"},
    {"zhHans": "deadline 当前，先活下来", "en": "Deadline first, survival second", "zhHant": "deadline 當前，先活下來"},
    {"zhHans": "happy hour 有约，社交也是训练", "en": "Happy hour. Socializing counts", "zhHant": "happy hour 有約，社交也是訓練"},
    {"zhHans": "身体说不，我尊重它", "en": "My body said no, and I respect it", "zhHant": "身體說不，我尊重它"},
    {"zhHans": "今天是战略性休息", "en": "Today is a strategic rest day", "zhHant": "今天是戰略性休息"}
  ]'::jsonb)
  returning *
)
insert into public.disclaimer_dice_events (dice)
select jsonb_build_object('version', 1, 'lines', lines) from first;
