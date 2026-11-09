-- A squad's weekly goal counts 训练 now, several on one day each (人均 N 次), not days trained
-- (Tracy, 2026-11-09). The 战报's last page shows the squad's `ending.done` against that goal,
-- so the stories frozen before this counted days in it: count them again, once, as 训练 the
-- members of the story sent to the squad that week before it froze. Nothing else in a story
-- changes, and stories stay frozen after.

alter table public.week_stories disable trigger week_stories_frozen;

update public.week_stories as story
set story = jsonb_set(
  story.story,
  '{ending,done}',
  to_jsonb((
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
      and check_in.created_at < story.written_at
  ))
)
where story.story ? 'ending';

alter table public.week_stories enable trigger week_stories_frozen;
