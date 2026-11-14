-- The teammate push (a squadmate's 训练, told as it is posted) moves from 通知's switch
-- (`dailyProgress`) to a switch of its own, the push topic `teammate`. A member who had turned
-- 通知 off had turned this push off with it, so they keep it off: their choice is carried over
-- once, and logged like any flip. Everyone else has no row, which means on.
with carried as (
  insert into public.push_settings (member_id, topic, enabled)
  select member_id, 'teammate', false
  from public.push_settings
  where topic = 'dailyProgress' and not enabled
  on conflict (member_id, topic) do nothing
  returning member_id, topic, enabled
)
insert into public.push_setting_events (member_id, topic, enabled)
select member_id, topic, enabled from carried;
