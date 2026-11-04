-- Six more sport kits (Tracy, 2026-11-04): cycling (the helmet and bike), boxing (gloves),
-- basketball, soccer, ski (skis and poles) and snowboard. Each prop opens on the member's first
-- 练了 in its sports, as the first props do, and each kit's move becomes one the weekly awards
-- may pick, so it gets a description here.

insert into public.unlock_rules (kind, item_id, sports, after) values
  ('prop', 'helmet', '{roadCycling,mountainBiking,spin,bikeCommute}', 1),
  ('prop', 'gloves', '{boxing,kickboxing,jiuJitsu,martialArts}', 1),
  ('prop', 'basketball', '{basketball}', 1),
  ('prop', 'soccerball', '{soccer}', 1),
  ('prop', 'skis', '{ski}', 1),
  ('prop', 'snowboard', '{snowboard}', 1)
on conflict (kind, item_id) do nothing;

with changed as (
  update public.weekly_award_settings
  set moves = $moves${
    "cycling": "戴上头盔骑车猛蹬，按两下车铃（这周骑了车或上了动感单车的人）",
    "boxing": "戴着拳套护脸跳步，两记刺拳再一记重拳（这周练了拳击或格斗的人）",
    "basketball": "运球两下，起跳投篮，球划弧线飞出去（这周打了篮球的人）",
    "soccer": "脚、膝盖、脚颠球，最后挑起来双手接住（这周踢了足球的人）",
    "ski": "踩着双板蹲低左右压弯，雪杖点地扬起雪花（这周滑了双板的人）",
    "snowboard": "踩着单板张开手臂随雪包起伏，做个豚跳（这周滑了单板的人）"
  }$moves$::jsonb || moves
  where not (moves ?& array['cycling', 'boxing', 'basketball', 'soccer', 'ski', 'snowboard'])
  returning *
)
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 2,
  'model', model,
  'instructions', instructions,
  'moves', moves,
  'badges', badges
)
from changed;

-- Combat sports train with the gloves now, so the dumbbell's line keeps to strength.
with changed as (
  update public.weekly_award_settings
  set moves = jsonb_set(moves, '{strength}', '"举起哑铃推两下再秀肌肉（这周练了力量的人）"')
  where moves ->> 'strength' = '举起哑铃推两下再秀肌肉（这周练了力量或格斗的人）'
  returning *
)
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 2,
  'model', model,
  'instructions', instructions,
  'moves', moves,
  'badges', badges
)
from changed;
