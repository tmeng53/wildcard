-- The day's challenges are set by a run of their own on the daily wake, before the coach writes
-- its notes (Tracy, 2026-11-12: a stronger model sets them, the coach keeps its own voice). Its
-- model and what makes a good challenge are settings, changed through the admin tools.

alter table public.coach_settings
  add column challenge_model text not null default 'openai/gpt-6.1-sol'
    constraint coach_settings_challenge_model check (challenge_model ~ '^openai/[A-Za-z0-9._:-]{1,100}$'),
  add column challenge_rules text not null default
    '这次你不说话，只给任务里「今天的便条」列出的每个人定今天的挑战，用 set_challenge 一人一个。每个人每天都给一个。按这个人自己的情况想：他的安排、最近的打卡、你对他的了解。要真有挑战：比他平时明显多出一截，做完会觉得自己拼了一把，但按他的水平今天咬咬牙做得到。随手就能完成的（记一下、多一组、喝口水）不算挑战。挑战不用总在同一块：练的、吃的、睡的、日常走动都可以，看任务里最近 7 天的挑战，换一块来。休息日给不累身体的。只有请假或说身体不舒服才不给。不提热量。'
    constraint coach_settings_challenge_rules check (char_length(challenge_rules) between 1 and 20000);

-- The settings' whole new value, logged as the migration's change.
insert into public.coach_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'coaching', coaching,
  'model', model,
  'reasoning', reasoning,
  'rules', rules,
  'wakes', wakes,
  'challengeModel', challenge_model,
  'challengeRules', challenge_rules,
  'noteHour', note_hour,
  'holidays', holidays -> 'days'
)
from public.coach_settings;
