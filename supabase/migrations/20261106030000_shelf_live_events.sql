-- Live events for 商店街: a `shelf` event tells the open app that what a member's street shows may
-- have changed, so it reads `GET /me/unlocks` again at once instead of on its next cold start
-- (Tracy, 2026-11-06: TURKEY TROT stayed hidden until the app was killed). Its payload is
-- {"version": 1, "kind": "shelf", "member": <member id, or null for everyone>}; the app reads the
-- shelf itself, so the event carries nothing else. A switch's scheduled day starting or ending
-- changes nothing in the database and so tells nothing: the app also reads the shelf again on each
-- return to the front and each time 我 or 商店街 opens.

-- A change to the stores, pieces, their rules or a switch: every member's street.
create function public.shelf_live_event_everyone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_notify(
    'live_events',
    json_build_object('version', 1, 'kind', 'shelf', 'member', null)::text
  );
  return null;
end;
$$;

create trigger shelf_live_event
  after insert on public.switch_events
  for each statement execute function public.shelf_live_event_everyone();

create trigger shelf_live_event
  after insert on public.store_events
  for each statement execute function public.shelf_live_event_everyone();

create trigger shelf_live_event
  after insert on public.piece_events
  for each statement execute function public.shelf_live_event_everyone();

create trigger shelf_live_event
  after insert on public.unlock_rule_events
  for each statement execute function public.shelf_live_event_everyone();

-- An unlock, a coach's gift or a switch preview: that member's street.
create function public.shelf_live_event_member()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_notify(
    'live_events',
    json_build_object('version', 1, 'kind', 'shelf', 'member', new.member_id)::text
  );
  return null;
end;
$$;

create trigger shelf_live_event
  after insert on public.member_unlocks
  for each row execute function public.shelf_live_event_member();

create trigger shelf_live_event
  after insert on public.coach_gifts
  for each row execute function public.shelf_live_event_member();

create trigger shelf_live_event
  after insert or update on public.switch_previews
  for each row execute function public.shelf_live_event_member();
