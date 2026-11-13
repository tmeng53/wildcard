-- The day's challenges are set by a run of their own on the daily wake, before the coach writes
-- its notes (Tracy, 2026-11-12), so a stronger model can set them while the coach keeps its own
-- voice; the coach's own model to begin with (Tracy, 2026-11-13: cost). Its model and what makes
-- a good challenge are settings, changed through the admin tools.

alter table public.coach_settings
  add column challenge_model text not null default 'openai/gpt-6-luna'
    constraint coach_settings_challenge_model check (challenge_model ~ '^openai/[A-Za-z0-9._:-]{1,100}$'),
  add column challenge_rules text not null default
    '这次你不说话，只给任务里「今天的便条」列出的每个人定今天的挑战，用 set_challenge 一人一个。每个人每天都给一个。按这个人自己的情况想：他的安排、最近的打卡、你对他的了解。要真有挑战：比他平时明显多出一截，做完会觉得自己拼了一把，但按他的水平今天咬咬牙做得到。随手就能完成的（记一下、多一组、喝口水）不算挑战。挑战不用总在同一块：练的、吃的、睡的、日常走动都可以，看任务里最近 7 天的挑战，换一块来。休息日给不累身体的。只有请假或说身体不舒服才不给。不提热量。

下面是一张挑战清单（动作和单位），从里面给每个人挑最合适的一个，数量按他的情况定。清单之外有更合适的，也可以自己想，照同样的格式。
力量：练力量（分钟）、练上肢（分钟）、练臀腿（分钟）、练背（分钟）、练核心（分钟）、做深蹲（个）、做高脚杯深蹲（个）、做保加利亚分腿蹲（个）、做弓步蹲（个）、做臀桥（个）、做俯卧撑（个）、做跪姿俯卧撑（个）、做引体向上（个）、做反向划船（个）、做哑铃划船（个）、做硬拉（组）、做罗马尼亚硬拉（个）、做卧推（组）、做肩推（组）、做平板支撑（秒）、做侧平板支撑（秒）、做死虫（个）、做卷腹（个）、做悬垂举腿（个）、做农夫行走（米）、做壶铃摆荡（个）、慢放下放（次）、加一组主项（组）、试一个新动作（个）、练单腿平衡（秒）、做靠墙静蹲（秒）、做提踵（个）
有氧：跑步（公里）、慢跑（分钟）、间歇跑（组）、冲刺跑（组）、爬坡走（分钟）、跳绳（个）、骑车（公里）、动感单车（分钟）、游泳（米）、划船机（米）、椭圆机（分钟）、爬楼梯（层）、开合跳（个）、波比跳（个）、高抬腿（秒）、登山跑（秒）、跳操（分钟）、跳舞（分钟）、徒步（公里）、滑冰（分钟）
球和项目：打球（分钟）、练发球（个）、练接发（个）、练反手（球）、练正手（球）、练步法（分钟）、练截击（球）、对墙练球（分钟）、投篮（个）、练运球（分钟）、颠球（个）、攀岩（条线）、练瑜伽（分钟）、练普拉提（分钟）、练太极（分钟）、打一场比赛（场）、约人一起练（人）、试一个新运动（项）
吃的：吃蔬菜（克）、吃绿叶菜（份）、吃水果（份）、加蛋白质（克）、吃鸡蛋（个）、喝牛奶（杯）、喝酸奶（杯）、吃豆腐（克）、吃豆类（克）、吃鱼（克）、吃鸡胸（克）、吃瘦肉（克）、吃全谷主食（碗）、吃杂粮（碗）、吃燕麦（碗）、吃坚果（把）、吃深色蔬菜（份）、吃不同颜色的菜（种）、搭配食材（种）、做健康餐（顿）、自己做饭（顿）、带便当（份）、备菜（份）、试一道新菜（道）、吃早餐（顿）、早餐加蛋白质（克）、练后补一顿（顿）、喝水（杯）、喝汤（碗）、换掉含糖饮料（杯）、少喝一杯奶茶（杯）、细嚼慢咽每顿（分钟）、晚饭吃到七分饱（顿）、零食换成水果（次）、外卖换成自己做（顿）、吃饭不看手机（顿）、晚饭早点吃（分钟）、睡前不再进食（小时）
睡的：早睡（分钟）、睡够（小时）、睡前放下手机（分钟）、关灯前读书（分钟）、午睡（分钟）、固定起床时间（天）、睡前拉伸（分钟）、睡前泡脚（分钟）、睡前不看工作（小时）、睡前写下明天的事（条）、下午不喝咖啡（小时）、卧室不带手机（晚）
走动：走路（步）、快走（分钟）、饭后散步（分钟）、爬楼代替电梯（次）、每小时起身走动（次）、站着办公（分钟）、走路通勤（公里）、提前一站下车走路（站）、遛狗（分钟）、户外晒太阳（分钟）、边打电话边走（分钟）、午休出去走走（分钟）、走到远一点的店（次）、陪家人散步（分钟）、做家务（分钟）、大扫除（分钟）
恢复：拉伸（分钟）、动态拉伸（分钟）、泡沫轴放松（分钟）、筋膜球放松（分钟）、做肩颈放松（组）、做髋部放松（组）、做冥想（分钟）、做深呼吸（组）、热身（分钟）、冷身（分钟）、泡澡（分钟）、按摩放松（分钟）、做正念散步（分钟）、发呆放空（分钟）、休息日完全不练（天）、记录今天的心情（条）
生活：记下训练重量（个动作）、给队友加油（人）、拍一张训练照（张）、规划明天的训练（项）、准备好明天的运动包（个）、整理运动装备（件）、读一篇运动知识（篇）、学一个新动作的要领（个）、户外活动（分钟）、远离屏幕（分钟）'
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
