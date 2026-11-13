-- A coach may pass on what a member asked for under a post (a feature they want, something
-- broken) as feedback from that member, filed like 意见反馈 (Tracy, 2026-11-12). Such a message
-- comes from no app, so it has no app facts: it says instead which coach heard it, where, and
-- the member's own words it heard it in.
alter table public.feedback alter column app drop not null;

-- The coach, squad, check-in and, when it was said in one, comment, and the member's own words,
-- as `{"version": 1, ...}`. A message is from the app or from a coach, never both.
alter table public.feedback add column relayed jsonb;

alter table public.feedback add constraint feedback_one_source
  check ((app is null) <> (relayed is null));

-- A coach's message carries no screenshots.
alter table public.feedback add constraint feedback_relayed_no_screenshots
  check (relayed is null or cardinality(screenshots) = 0);
