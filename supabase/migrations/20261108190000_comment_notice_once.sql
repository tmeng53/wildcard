-- A comment's notice is told to each member once, even when its event is delivered twice
-- (Pub/Sub delivers at least once).
create unique index notices_one_comment_each
  on public.notices (member_id, (subject ->> 'comment'))
  where kind = 'comment' and subject ? 'comment';
