-- The coach's dream (Tracy, 2026-11-08): once a night, before the day's daily wake, the coach
-- rewrites its squad's memory from the day before, keeping only what lasts and dropping what is
-- stale or contradicted. One a squad a day, queued like the daily wake.
alter table public.coach_wakes
  drop constraint coach_wakes_reason_check,
  add constraint coach_wakes_reason_check
    check (reason in ('checkIn', 'daily', 'comment', 'dream')),
  drop constraint coach_wakes_check1,
  add constraint coach_wakes_day_check check ((reason in ('daily', 'dream')) = (day is not null));

create unique index coach_wakes_one_dream_a_day on public.coach_wakes (squad_id, day)
  where reason = 'dream';
