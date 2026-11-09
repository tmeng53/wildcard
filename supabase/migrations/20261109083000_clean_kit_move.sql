-- 大扫除 trains with the broom (Tracy, 2026-11-09): the `clean` kit's move becomes one the
-- weekly awards may pick, so it gets a description here.

with changed as (
  update public.weekly_award_settings
  set moves = moves || '{"clean": "握着扫帚左右扫地，扬起两团灰（这周大扫除的人）"}'::jsonb
  where not (moves ? 'clean')
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
