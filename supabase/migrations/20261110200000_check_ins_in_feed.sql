-- 发布到动态 replaces 仅自己可见 (Tracy, 2026-11-10). A check-in always goes to the member's
-- squad and counts for it; `in_feed` says whether it is also a post in the squad's 动态. Set
-- when it is posted and never changed, like its audience.
alter table public.check_ins
  add column in_feed boolean not null default true;

-- The 仅自己可见 posts made while in a squad become records the squad counts but that are not in
-- its 动态, as a check-in with the switch off is now (Tracy, 2026-11-10). A check-in made before
-- its member joined their squad stays outside it, as before.
with private as (
  select c.id, m.squad_id
  from public.check_ins as c
  join public.squad_members as m on m.member_id = c.member_id
  where c.created_at >= m.joined_at
    and not exists (select 1 from public.check_in_squads as s where s.check_in_id = c.id)
),
shared as (
  insert into public.check_in_squads (check_in_id, squad_id, position)
  select id, squad_id, 1 from private
  returning check_in_id
)
update public.check_ins
set in_feed = false
where id in (select check_in_id from shared);
