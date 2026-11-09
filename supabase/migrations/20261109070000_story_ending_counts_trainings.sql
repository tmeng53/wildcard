-- A squad's weekly goal counts 训练 now, several on one day each (人均 N 次), not days trained
-- (Tracy, 2026-11-09). The 战报's last page shows the squad's `ending.done` against that goal,
-- so the stories frozen before this counted days in it: count them again, once, as the API's
-- freeze counts them: 训练 the members of the story sent to the squad that week, made before
-- the awards (Sunday 8pm on the squad's clock that week: its newest time zone set for a week up
-- to it, New York without one). A post that arrived after the freeze with an earlier time (sent
-- late from a phone's outbox) is counted too, since the arrival time isn't kept. A story whose
-- 训练 were all deleted since loses its ending, as the freeze leaves it out when nothing was
-- trained. Nothing else in a story changes, and stories stay frozen after.

alter table public.week_stories disable trigger week_stories_frozen;

with recount as (
  select
    story.squad_id,
    story.week_start,
    (
      select count(*)
      from public.check_ins as check_in
      join public.check_in_squads as audience
        on audience.check_in_id = check_in.id and audience.squad_id = story.squad_id
      join public.week_story_members as member
        on member.squad_id = story.squad_id
        and member.week_start = story.week_start
        and member.member_id = check_in.member_id
      where check_in.kind = 'trained'
        and check_in.day between story.week_start and story.week_start + 6
        and check_in.created_at < ((story.week_start + 6) + time '20:00') at time zone coalesce(
          (
            select zone.time_zone
            from public.squad_time_zones as zone
            where zone.squad_id = story.squad_id and zone.week_start <= story.week_start
            order by zone.week_start desc, zone.id desc
            limit 1
          ),
          'America/New_York'
        )
    ) as done
  from public.week_stories as story
  where story.story ? 'ending'
)
update public.week_stories as story
set story = case
  when recount.done = 0 then story.story - 'ending'
  else jsonb_set(story.story, '{ending,done}', to_jsonb(recount.done))
end
from recount
where story.squad_id = recount.squad_id and story.week_start = recount.week_start;

alter table public.week_stories enable trigger week_stories_frozen;
