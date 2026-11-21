-- 解散小队 (Tracy, 2026-11-21): the captain ends the squad for everyone at once. Each member it
-- takes out, the captain too, is logged as `disbanded`, with the captain as the actor, apart from
-- one who left or was removed; the squad then ends as when its last member leaves, with an
-- `ended` row in its log.
alter table public.squad_membership_events drop constraint squad_membership_events_kind_check;
alter table public.squad_membership_events
  add constraint squad_membership_events_kind_check
  check (kind in ('joined', 'left', 'removed', 'disbanded'));
