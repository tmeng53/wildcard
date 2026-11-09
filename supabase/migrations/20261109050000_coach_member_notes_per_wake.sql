-- A member's coach notes are no longer one a day: a wake writes each member at most one, and the
-- coach's own wakes already run once a squad a day (`coach_wakes`), so the day was a second,
-- stricter rule that also kept an admin from sending themselves a test note, and would keep any
-- later wake (an evening one) from writing. A note without a wake (an admin's own) is never held.
alter table public.coach_member_notes
  drop constraint coach_member_notes_squad_id_member_id_day_key;

create unique index coach_member_notes_one_a_wake
  on public.coach_member_notes (wake_id, member_id) where wake_id is not null;

-- The day's notes of a squad, as the challenge reads look them up.
create index coach_member_notes_squad_day on public.coach_member_notes (squad_id, day, id);
