-- 头衔徽章 colours become data: each colour in the badge catalog carries its tone (#RRGGBB),
-- which the API sends with every badge, so a new colour is a settings change and no app release.
-- It runs only after an API that reads colours with tones is live, since the one before can't.
-- The catalog grows from the five scenes' colours to eleven from the design system: the six
-- scenes' signatures and five of the clothes' swatches. Shapes and glyphs stay as they are.
update public.weekly_award_settings
set badges = jsonb_set(badges, '{colours}', $colours$[
  {"id": "pool", "tone": "#079BB8", "meaning": "泳池青：水、冷静、清爽"},
  {"id": "track", "tone": "#E65345", "meaning": "跑道红：热烈、速度、上头"},
  {"id": "gym", "tone": "#4A6C8C", "meaning": "钢蓝：力量、规律、靠谱"},
  {"id": "tennis", "tone": "#4F6B22", "meaning": "草地绿：户外、清新、自然"},
  {"id": "climbing", "tone": "#8E4A2C", "meaning": "岩砖：耐力、接地气、慢慢来"},
  {"id": "ski", "tone": "#16384D", "meaning": "冰川蓝：冬天、冷静到底"},
  {"id": "cobalt", "tone": "#2D5BA0", "meaning": "钴蓝：专注、认真、一丝不苟"},
  {"id": "mint", "tone": "#278C5E", "meaning": "薄荷：吃得健康、清爽"},
  {"id": "honey", "tone": "#A0760E", "meaning": "蜂蜜金：荣誉、第一名"},
  {"id": "lavender", "tone": "#9062DE", "meaning": "薰衣草：深夜、松弛、有点浪漫"},
  {"id": "graphite", "tone": "#1F2128", "meaning": "石墨：酷、低调、硬核"}
]$colours$::jsonb);

-- The log holds the whole settings after every change.
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 2,
  'model', model,
  'instructions', instructions,
  'moves', moves,
  'badges', badges
)
from public.weekly_award_settings;
