-- 小队菜单 on the Sunday 战报 (Tracy, 2026-11-12): a member's rated meals on it are posts of
-- theirs, each a row of its own so that deleting the meal takes it with it. A member may have
-- several on it, so a post's row is keyed by its check-in too.
alter table public.week_story_posts
  drop constraint week_story_posts_role_check,
  add constraint week_story_posts_role_check
    check (role in ('hottest', 'bestDisclaimer', 'menu')),
  drop constraint week_story_posts_pkey,
  add primary key (squad_id, week_start, member_id, role, check_in_id);
