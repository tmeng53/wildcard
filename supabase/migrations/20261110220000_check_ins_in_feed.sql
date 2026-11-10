-- 发布到动态 replaces 仅自己可见 (Tracy, 2026-11-10). A check-in always goes to the member's
-- squad and counts for it; `in_feed` says whether it is also a post in the squad's 动态. Set
-- when it is posted and never changed, like its audience.
--
-- The 仅自己可见 posts already made are turned into check-ins only recorded by a later
-- migration, once the API that reads `in_feed` is live: the API still running while this one is
-- applied lists a squad's 动态 by `check_in_squads` alone, and would show them.
alter table public.check_ins
  add column in_feed boolean not null default true;
