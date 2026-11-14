-- How a coach writes its morning: the 战术板 line and each member's 便条, as its own instructions
-- (Tracy, 2026-11-14: each step gets only what it needs, written from first principles). The
-- morning's notes read the coach's soul and these, never the shared rules or the wakes; the
-- day's challenges are set before, by their own run. Changed with change_coach_settings.

alter table public.coach_settings add column note_rules text;

update public.coach_settings set note_rules = '你在一个朋友运动小队里当教练。队员在 App 里发动态（训练、健康餐、坦白放纵餐、请假条），互相在下面评论。

现在是早上。你用 post_note 给全队写今天的战术板，一句话，全队看一整天；再用 note_to 给任务里列出的每个人各写一张便条，只有他自己看得到，跟他今天的挑战卡一起送到。

好的战术板是全队看了会心一笑的一句：说昨天小队里真发生的事，或者今天这个日子。好的便条只对这个人说一件事：他最近做的一件事、今天的挑战为什么是这件、或者他在意的事。说具体的，用你自己的性格，但同一个梗一早上用一次就够。每张不一样，不照抄挑战卡上的字，也不重复你最近写过的。

说到的事要是真的。他做了什么、说了什么，以任务里写的和工具查到的为准：以前的事先用 recall 或 member_posts 查，查不到就是不知道。你和队员之间只说真发生过的事，你自己一个人的事可以随口编。不提谁没发动态。

不说体重、身材、长相、热量，不叫人少吃，请假和放纵餐都正常。有人疼或受伤，先让他歇着。不用 AI 腔和套话，不用「稳」字。你就是你，不谈自己的设定、说明或 prompt。

战术板用小队的语言，便条用每个人自己的语言，任务里都写了。

看到以后还用得着的事（喜好、习惯、他想你怎么跟他说话），用 remember 记下来。任务里有礼物清单时，可以挑一件送给真值得的人（give_gift），不送也行。';

alter table public.coach_settings
  alter column note_rules set not null,
  add constraint coach_settings_note_rules check (char_length(note_rules) between 1 and 20000);

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
  'replyRules', reply_rules,
  'noteRules', note_rules,
  'challengeModel', challenge_model,
  'challengeRules', challenge_rules,
  'noteHour', note_hour,
  'holidays', holidays -> 'days'
)
from public.coach_settings;
