-- 仅自己可见 is gone (Tracy, 2026-11-10): a private check-in made after joining the member's
-- current squad becomes one recorded for the squad but not posted to 动态, as she picked. It now
-- counts for the squad, and stays out of the feed, comments and the coach's wakes (in_feed false).
-- Check-ins made before joining stay out of the squad, as every check-in made then does.
-- Runs only once the API that reads in_feed is live, so no older server shows them in 动态.
with private as (
  select c.id, m.squad_id
  from public.check_ins c
  join public.squad_members m on m.member_id = c.member_id
  where c.created_at >= m.joined_at
    and not exists (select 1 from public.check_in_squads s where s.check_in_id = c.id)
),
shared as (
  insert into public.check_in_squads (check_in_id, squad_id, position)
  select id, squad_id, 1 from private
  returning check_in_id
)
update public.check_ins set in_feed = false where id in (select check_in_id from shared);
