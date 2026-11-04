-- 头衔徽章: each weekly title comes with a badge the model picks, and a member wears one title on
-- their player card.

-- What the model may pick a title's badge from: shapes and colours the app can draw, and glyphs,
-- which are SF Symbol names, so a new glyph is a change here and nothing else. Each comes with
-- what it means, for the model. Kept with the rest of the award settings and logged with them.
-- Every rule about the values is the API's; the database keeps only what keeps the row whole.
alter table public.weekly_award_settings
  add column badges jsonb not null default $badges${
    "shapes": [
      {"id": "shield", "meaning": "盾牌：守住了、扛住了、说到做到"},
      {"id": "hexagon", "meaning": "六边形：硬核、全能、一板一眼"},
      {"id": "circle", "meaning": "圆：温和、圆满、松弛"},
      {"id": "scallop", "meaning": "花边：可爱、庆祝、有点得意"}
    ],
    "colours": [
      {"id": "pool", "meaning": "青蓝：水、冷静、清爽"},
      {"id": "track", "meaning": "红：热烈、速度、上头"},
      {"id": "gym", "meaning": "钢蓝：力量、规律、靠谱"},
      {"id": "tennis", "meaning": "草绿：健康、清新、自然"},
      {"id": "climbing", "meaning": "砖棕：耐力、接地气、慢慢来"}
    ],
    "glyphs": [
      {"id": "sun.max.fill", "meaning": "太阳：早起、白天练"},
      {"id": "moon.fill", "meaning": "月亮：深夜、熬夜还练"},
      {"id": "snowflake", "meaning": "雪花：冷面、淡定、不说话"},
      {"id": "leaf.fill", "meaning": "叶子：健康餐、清淡"},
      {"id": "heart.fill", "meaning": "爱心：对自己好、照顾队友"},
      {"id": "bolt.fill", "meaning": "闪电：爆发、突然很猛"},
      {"id": "flame.fill", "meaning": "火：拼、燃、停不下来"},
      {"id": "doc.text.fill", "meaning": "纸条：请假条"},
      {"id": "dumbbell.fill", "meaning": "哑铃：力量训练、举铁"},
      {"id": "figure.run", "meaning": "跑步的人：跑步、有氧"},
      {"id": "figure.pool.swim", "meaning": "游泳的人：游泳"},
      {"id": "tennisball.fill", "meaning": "网球：球类运动"},
      {"id": "mountain.2.fill", "meaning": "山：攀岩、徒步、爬坡"},
      {"id": "drop.fill", "meaning": "水滴：出汗、喝水"},
      {"id": "fork.knife", "meaning": "刀叉：吃、放纵餐"},
      {"id": "cup.and.saucer.fill", "meaning": "咖啡杯：悠闲、续命"},
      {"id": "bed.double.fill", "meaning": "床：休息、睡够了"},
      {"id": "alarm.fill", "meaning": "闹钟：准时、守时、卡点"},
      {"id": "tortoise.fill", "meaning": "乌龟：慢慢来、细水长流"},
      {"id": "hare.fill", "meaning": "兔子：快、说练就练"},
      {"id": "camera.fill", "meaning": "相机：爱拍照、照片精彩"},
      {"id": "music.note", "meaning": "音符：有节奏、跳舞"},
      {"id": "sparkles", "meaning": "闪光：惊喜、亮眼"},
      {"id": "star.fill", "meaning": "星星：全能、闪亮"},
      {"id": "crown.fill", "meaning": "皇冠：第一、本周最强"}
    ]
  }$badges$::jsonb
    check (jsonb_typeof(badges) = 'object');

-- The default was for the existing row only: the API always saves the catalog whole.
alter table public.weekly_award_settings alter column badges drop default;

-- The log holds the whole settings after every change, so it gets them with the catalog too.
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 2,
  'model', model,
  'instructions', instructions,
  'moves', moves,
  'badges', badges
)
from public.weekly_award_settings;

-- The title a member wears on the front of their player card and beside their name on the home:
-- one they won, by its words. Null until they pick one, and the app then shows their latest.
-- Whether they won it is the API's to check. Logged with the rest of the profile, so replaying
-- profile_events rebuilds it too.
alter table public.profiles
  add column equipped_title text check (char_length(equipped_title) between 1 and 40);

alter table public.profile_events
  add column equipped_title text;
