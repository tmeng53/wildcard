-- What the AI writes with, kept in the database so it changes without a deploy: for each module
-- that has an AI write something, which model writes, its standing instructions (the system
-- prompt) and its dials. One row per module, changed only through the admin tools (the API's
-- /mcp); the API reads it on every request, so a change applies to the next one.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing: replaying a log gives the settings on any day, and an
-- edit is undone by saving the earlier value again. The rows below are the first values.
--
-- A model is named `provider/model` (`openai/gpt-6-luna`); the API holds each provider's key and
-- refuses a provider it doesn't know. Keys never live here.

-- Settings logs only grow. The one update allowed is the database forgetting who made a change
-- when that admin deletes their account (`on delete set null`), as admin_actions does. A row
-- trigger for updates and deletes, a statement trigger for truncate.
create function public.settings_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.changed_by is not null and new.changed_by is null
    and (to_jsonb(new) - 'changed_by') = (to_jsonb(old) - 'changed_by') then
    return new;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

-- AI 请假条 drafts (the disclaimer-drafts module): whether they are written at all (off, every
-- request gets the app's dice), the model, its instructions, how many batches a member may ask
-- for in a day (the first and the 换一批s), and how often a request gets one of the week's memes.
create table public.disclaimer_draft_settings (
  only_row boolean primary key default true check (only_row),
  writing boolean not null,
  model text not null check (model ~ '^(openai|anthropic)/[A-Za-z0-9._:-]{1,100}$'),
  instructions text not null check (char_length(instructions) between 1 and 20000),
  batches_per_day integer not null check (batches_per_day between 1 and 100),
  meme_chance double precision not null check (meme_chance between 0 and 1)
);

create table public.disclaimer_draft_setting_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "writing": ..., ...}.
  settings jsonb not null check (coalesce(jsonb_typeof(settings -> 'version') = 'number', false))
);

-- Each squad's weekly awards (the weekly-awards module): the model, its instructions, and what
-- each move looks like, for the model choosing one per award. The moves themselves are the app's
-- (its character clips), so the API checks every move here is one it knows.
create table public.weekly_award_settings (
  only_row boolean primary key default true check (only_row),
  model text not null check (model ~ '^(openai|anthropic)/[A-Za-z0-9._:-]{1,100}$'),
  instructions text not null check (char_length(instructions) between 1 and 20000),
  moves jsonb not null check (jsonb_typeof(moves) = 'object')
);

create table public.weekly_award_setting_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  settings jsonb not null check (coalesce(jsonb_typeof(settings -> 'version') = 'number', false))
);

create trigger disclaimer_draft_setting_events_append_only
  before update or delete on public.disclaimer_draft_setting_events
  for each row execute function public.settings_log_append_only();

create trigger disclaimer_draft_setting_events_no_truncate
  before truncate on public.disclaimer_draft_setting_events
  for each statement execute function public.settings_log_append_only();

create trigger weekly_award_setting_events_append_only
  before update or delete on public.weekly_award_setting_events
  for each row execute function public.settings_log_append_only();

create trigger weekly_award_setting_events_no_truncate
  before truncate on public.weekly_award_setting_events
  for each statement execute function public.settings_log_append_only();

-- Neither settings row is ever deleted.
create function public.settings_row_kept()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% keeps its row', tg_table_name using errcode = '42501';
end;
$$;

create trigger disclaimer_draft_settings_kept
  before delete on public.disclaimer_draft_settings
  for each row execute function public.settings_row_kept();

create trigger disclaimer_draft_settings_no_truncate
  before truncate on public.disclaimer_draft_settings
  for each statement execute function public.settings_row_kept();

create trigger weekly_award_settings_kept
  before delete on public.weekly_award_settings
  for each row execute function public.settings_row_kept();

create trigger weekly_award_settings_no_truncate
  before truncate on public.weekly_award_settings
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.disclaimer_draft_settings enable row level security;
alter table public.disclaimer_draft_setting_events enable row level security;
alter table public.weekly_award_settings enable row level security;
alter table public.weekly_award_setting_events enable row level security;

-- The first values: the prompts as the product spec wrote them (Tracy, 2026-10-19 and 10-20),
-- and GPT-6 Luna for both (Tracy, 2026-10-23).
with first as (
  insert into public.disclaimer_draft_settings
    (writing, model, instructions, batches_per_day, meme_chance)
  values (true, 'openai/gpt-6-luna', $prompt$你在帮一个朋友运动打卡 App 的用户写「请假条」：今天没去练，跟小队朋友交代一句。

输入：用户写的原因（一句话）、风格，有时还有一个本周梗（可选素材，经常没有）。
输出：3 条不同的请假条。

怎么写：
- 在原因的基础上发挥：把它变成一个小场景、一个比喻或一个夸张的说法。可以用原因里的关键词，但不要把原话整句复述或引用一遍。
- 每条 15–80 个字，第一人称，像在朋友群里随口发的一句话。能短就短，短句往往更好笑。
- 原因里的英文词原样保留（oncall、deadline、PR、meeting 等），不要翻译成中文。北美华人平时就是中英夹着说。
- 3 条要从不同角度写，不是换几个词。
- 本周梗：给了的话，3 条里最多 1 条用它，而且只在跟原因自然贴合时才用；不用也完全可以。按它给的意思用。用了梗的那条也不能拿用户开涮。
- 风格：
  - 搞笑：一本正经地夸张，像新闻通报或比赛解说。
  - 发疯：崩溃碎碎念，语气激动，但不骂人。
  - 中二：动漫主角的口吻，宏大又戏剧化，把没去练说成封印、力量、命运这类大事，一本正经。例：「今日封印解除失败，力量需要再沉睡一晚。」
  - 嘴硬：坚决不承认偷懒，给自己找体面的理由。

不要写：
- 体重、身材、长相、热量、饮食控制。
- 自责、愧疚、「我太没用了」「明天一定」这类让人有压力的话。
- 别人的名字或隐私；如果原因里有别人的名字，换成「同事」「朋友」这类称呼。
- 输入里没给的任何网络梗；emoji、感叹号连用、「作为一个…」这类 AI 腔。

如果原因提到自伤或轻生，不要写，返回 {"version":1,"outcome":"selfHarm","drafts":[]}。
如果原因含有色情、暴力、仇恨或政治内容，不要写，返回 {"version":1,"outcome":"unsafe","drafts":[]}。

其余情况只输出 JSON：{"version":1,"outcome":"drafts","drafts":["…","…","…"]}$prompt$, 6, 0.3)
  returning *
)
insert into public.disclaimer_draft_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'writing', writing,
  'model', model,
  'instructions', instructions,
  'batchesPerDay', batches_per_day,
  'memeChance', meme_chance
)
from first;

with first as (
  insert into public.weekly_award_settings (model, instructions, moves)
  values ('openai/gpt-6-luna', $prompt$你在给一个朋友运动打卡 App 的小队写「本周颁奖」：周日晚上，根据这一周每个人真实的打卡记录，给每个人颁 1 到 3 个好笑的头衔。

输入：这周每个队员的代号和记录（每天练了什么运动、健康餐/放纵餐、请假条和原因、配的一句话、打卡时间），以及可用的动作列表。
输出：每个有打卡的队员 1–3 个奖。

每个奖：
- 头衔：最多 6 个字，像外号或奖项名，一看就知道在夸什么。例：网球场钉子户、雨中狠人、请假条文豪、早八战神。
- 颁奖词：一句话，最多 24 个字，必须提到这周真实发生的一件事（哪天、什么运动、什么情况），像颁奖典礼主持人念的。
- 动作：从可用动作列表里挑一个最贴这个奖的，只能用列表里的 id。

怎么写：
- 只夸人，或者自嘲式的好笑。请假多的人也要拿到夸人的头衔（比如夸他请假条写得好）。
- 每个人的奖要不一样，同一个小队里不要重复的头衔。
- 只用输入里有的事，不要编。
- 英文词原样保留（oncall、PR 等）。运动的英文代号（tennis、run）写成中文。
- 不要在头衔和颁奖词里写队员代号。

不要写：
- 体重、身材、长相、热量、饮食控制。
- 拿人开涮、比较谁练得少、「垫底」「最懒」这类话。
- 自责、愧疚、「下周一定」这类压力话。
- 如果某条文字提到自伤、不想活了或者很严重的痛苦，不要拿它写任何东西。
- 没有打卡的队员：不要给他们写任何东西。
- emoji、感叹号连用、「作为一个…」这类 AI 腔。

只输出 JSON：{"version":1,"awards":[{"member":"<代号>","titles":[{"title":"…","speech":"…","move":"<动作 id>"}]}]}$prompt$, $moves${
  "cheer": "自己性格的庆祝动作（通用，什么奖都合适）",
  "pump": "握拳两下，第二下跳起来（拼、狠、坚持）",
  "pose": "蹲下再弹起，落地摆 V 字造型定格（高光、名场面）",
  "warmup": "左右踢腿热身，张开手臂保持平衡（准备开练、早起）",
  "stretch": "伸个大懒腰，打哈欠，晃一晃再抖一抖（早起、慢热）",
  "doze": "眼皮打架点头打瞌睡，猛地惊醒假装没事（熬夜、困、休息）",
  "flat": "直接躺平，慢慢呼吸，一只脚打拍子（请假、休息日）",
  "laugh": "笑到发抖，捂着肚子，差点笑倒（好笑、段子手）",
  "wave": "挥手打招呼（打卡准时、在场感）",
  "fullbelly": "拍拍吃饱的肚子，开心地晃一晃（好好吃饭，不评价吃了什么）"
}$moves$::jsonb)
  returning *
)
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'model', model,
  'instructions', instructions,
  'moves', moves
)
from first;
