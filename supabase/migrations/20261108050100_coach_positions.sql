-- The order of 教练招聘会 (Tracy, 2026-11-08): each coach's place in the list squads hire from,
-- as data, so it changes through put_coach with no release or deploy. Coaches sharing a place
-- fall back to their ids.

alter table public.coaches add column position integer;

-- 毛头, 鸭梨娜, 企飞 first (Tracy, 2026-11-08), then any other coach by id.
update public.coaches as coach set position = ordered.position
from (
  select id, row_number() over (
    order by array_position(array['xiaohun', 'yalina', 'qifei'], id) nulls last, id
  ) as position
  from public.coaches
) as ordered
where coach.id = ordered.id;

alter table public.coaches
  alter column position set not null,
  add constraint coaches_position check (position between 1 and 1000);

-- The change, logged with each coach's whole new value, as the API stores it.
insert into public.coach_catalog_events (changed_by, coach_id, coach)
select null, id, jsonb_build_object(
  'version', 3,
  'id', id,
  'position', position,
  'tier', tier,
  'name', name,
  'title', title,
  'catchphrase', catchphrase,
  'background', background,
  'yearsCoaching', years_coaching,
  'experience', experience,
  'tags', to_jsonb(tags),
  'pay', pay,
  'style', style,
  'soul', soul,
  'look', look,
  'offered', offered
)
from public.coaches;
