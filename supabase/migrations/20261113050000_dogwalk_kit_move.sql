-- 遛狗 walks a dog on a leash (Tracy, 2026-11-12): the `dogwalk` kit's move becomes one the
-- weekly awards may pick, so it gets a description here.

with changed as (
  update public.weekly_award_settings
  set moves = moves || '{"dogwalk": "牵着狗遛弯，被狗拽了两下，一起蹦一下（这周遛狗的人）"}'::jsonb
  where not (moves ? 'dogwalk')
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
