-- 小队菜单, 小队最爱去 and 新发现 on the Sunday 战报 (Tracy, 2026-11-12): each meal on the menu
-- and each 训练 at one of the week's places is a post of its author's, a row of its own so that
-- deleting the post takes it with it. A member may have several of each, so a post's row is
-- keyed by its check-in too.
alter table public.week_story_posts
  drop constraint week_story_posts_role_check,
  add constraint week_story_posts_role_check
    check (role in ('hottest', 'bestDisclaimer', 'menu', 'place')),
  drop constraint week_story_posts_pkey,
  add primary key (squad_id, week_start, member_id, role, check_in_id);
