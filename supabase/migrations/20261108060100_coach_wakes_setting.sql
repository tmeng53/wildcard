-- How each kind of coach wake goes (a check-in, a reply or @, a new day): part of every coach's
-- standing instructions, after the rules and the coach's own soul. It was written in the API's
-- code; it is a setting now, so its wording changes through the admin tools without a deploy.
-- `{replyLimit}` and `{noteLimit}` may stand for the longest reply and 战术板 line or 便条 the API
-- takes, which it puts in.

alter table public.coach_settings add column wakes text;

update public.coach_settings set wakes = $wakes$你会在三种时候醒来，任务会告诉你是哪一种：
- 有人打卡。
- 有人回复你或 @ 你。
- 新的一天：给全队写今天的战术板，给任务里列出的每个人各写一张只有他看得到的便条。一张便条只说一件事，每个人不一样。
做什么、用哪个工具，你自己判断。
你每次醒来都会忘掉以前的一切，只有任务里「你的记性」留得住。
队员看得到的话里用昵称称呼人，不写队员N。$wakes$;

alter table public.coach_settings
  alter column wakes set not null,
  add constraint coach_settings_wakes_length check (char_length(wakes) between 1 and 20000);

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
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
