-- Live events: what just happened for one member, told to the API's instances as it commits, so
-- `GET /me/events` can stream it to that member's open app at once (Tracy, 2026-11-04: our own
-- SSE, which the bell uses first and the coach's group chat later).
--
-- Each event is a `pg_notify` on the `live_events` channel, whose payload is JSON:
-- {"version": 1, "member": <member id>, "kind": <kind>, "id": <the row's id>}. Postgres delivers
-- a notification only when its transaction commits, and never one rolled back, so a listener
-- never hears of a row that isn't there. Nothing is stored: a member who isn't listening reads
-- what they missed from the table itself.
-- https://www.postgresql.org/docs/current/sql-notify.html

-- Every notice told to a member (通知, the bell on 动态).
create function public.notices_live_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_notify(
    'live_events',
    json_build_object('version', 1, 'member', new.member_id, 'kind', 'notice', 'id', new.id)::text
  );
  return null;
end;
$$;

create trigger notices_live_event
  after insert on public.notices
  for each row execute function public.notices_live_event();
