-- The coach welcomes whoever joins its squad (Tracy, 2026-11-12): a `joined` wake, queued as the
-- member joins, on which the coach introduces itself and welcomes them in a note only they read,
-- delivered at once. One a member a squad a day (on the squad's clock), so joining again the
-- same day isn't welcomed twice; the member's account going takes their wake.
alter table public.coach_wakes
  add column member_id uuid references auth.users (id) on delete cascade,
  drop constraint coach_wakes_reason_check,
  add constraint coach_wakes_reason_check
    check (reason in ('checkIn', 'daily', 'comment', 'dream', 'joined')),
  drop constraint coach_wakes_day_check,
  add constraint coach_wakes_day_check
    check ((reason in ('daily', 'dream', 'joined')) = (day is not null)),
  add constraint coach_wakes_member_check check ((reason = 'joined') = (member_id is not null));

create unique index coach_wakes_one_welcome_a_day on public.coach_wakes (squad_id, member_id, day)
  where reason = 'joined';
