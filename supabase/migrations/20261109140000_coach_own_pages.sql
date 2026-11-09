-- Each coach keeps a page of its own in a squad's memory, `coaches/<coach id>.md`, which only
-- that coach reads (shown to it as `me.md`): a coach who comes back finds its page again, and a
-- new coach starts its own, so one coach's view of itself never becomes the next one's
-- (Tracy, 2026-11-09). It is no member's page, so `member_id` stays null.
alter table public.coach_files drop constraint coach_files_path_check;
alter table public.coach_files add constraint coach_files_path_check check (
  path in ('squad.md', 'memory.md')
  or path ~ '^people/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.md$'
  or path ~ '^coaches/[a-z][a-z0-9-]{1,39}\.md$'
);
