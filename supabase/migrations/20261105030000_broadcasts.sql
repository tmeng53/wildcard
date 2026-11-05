-- Broadcasts: a notice admins write once and send to every member (Tracy, 2026-11-04: "我可以一次
-- 性推送一些 notification", with an optional button that opens a place in the app; no holiday is
-- a concept of its own, a holiday is just one of these). Each member is told it on their first
-- open of the app while it runs, so a member who signs up meanwhile is told too; it then stays in
-- their 通知 like any other notice.
--
-- Changed only through admin tools. A broadcast is never changed in place: each save is a new row
-- with its whole value, and the newest row for an id is what it says now, so the table is its own
-- log (public.settings_log_append_only). A member's notice names the broadcast by id and shows
-- its words as they are now, so fixing a typo fixes it for everyone already told.
create table public.broadcasts (
  id bigint generated always as identity primary key,
  broadcast_id text not null check (broadcast_id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- {"version": 1, "title": {...}, "body"?: {...}, "action"?: {...}, "style": ...,
  --  "gifts": [...], "startsAt": ..., "endsAt"?: ...}, as the API checks it.
  broadcast jsonb not null check (coalesce(jsonb_typeof(broadcast -> 'version') = 'number', false))
);

create index broadcasts_by_id on public.broadcasts (broadcast_id, id desc);

create trigger broadcasts_append_only
  before update or delete on public.broadcasts
  for each row execute function public.settings_log_append_only();

create trigger broadcasts_no_truncate
  before truncate on public.broadcasts
  for each statement execute function public.settings_log_append_only();

alter table public.broadcasts enable row level security;

-- A member is told each broadcast once, however many opens race to tell them.
create unique index notices_one_broadcast_each
  on public.notices (member_id, (subject ->> 'broadcast'))
  where kind = 'broadcast';
