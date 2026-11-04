-- A member may now edit and delete their own check-ins (Tracy, 2026-11-02): the 「…」 on a post
-- opens 编辑 and 删除. An edit replaces the kind's fields and the photos; the kind, the day,
-- the time and the audience stay as posted.

-- Every version of a check-in, oldest first: the one posted, then each edit that changed
-- something, with the whole entry as saved (the kind's fields and the photos, the cover first).
-- Replaying it rebuilds what a post said at any moment. Written in the same transaction as the
-- change. Deleting the post, or the account, removes it with the post: deletion removes data.
create type public.check_in_event_kind as enum ('posted', 'edited');

create table public.check_in_events (
  id bigint generated always as identity primary key,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  kind public.check_in_event_kind not null,
  -- {"version": 1, "payload": <check_ins.payload>, "photos": [{"path", "width"?, "height"?}]}
  entry jsonb not null check (coalesce(jsonb_typeof(entry -> 'version') = 'number', false)),
  at timestamptz not null default now()
);

create index check_in_events_check_in_id_idx on public.check_in_events (check_in_id, id);

-- A row is never changed or removed, except when its post or its member is deleted: the
-- cascade runs after the parent row is gone, so it passes. A statement trigger refuses truncate.
create function public.check_in_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from public.check_ins where id = old.check_in_id)
    or not exists (select 1 from auth.users where id = old.member_id)
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger check_in_events_append_only
  before update or delete on public.check_in_events
  for each row execute function public.check_in_log_append_only();

create trigger check_in_events_no_truncate
  before truncate on public.check_in_events
  for each statement execute function public.check_in_log_append_only();

-- The posts made before the log: each as it stands, as posted.
insert into public.check_in_events (check_in_id, member_id, kind, entry, at)
select
  c.id,
  c.member_id,
  'posted',
  jsonb_build_object(
    'version', 1,
    'payload', c.payload,
    'photos', coalesce(
      (
        select jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object('path', p.path, 'width', p.width, 'height', p.height))
          order by p.position
        )
        from public.check_in_photos p
        where p.check_in_id = c.id
      ),
      '[]'::jsonb
    )
  ),
  c.created_at
from public.check_ins c
order by c.created_at, c.id;

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.check_in_events enable row level security;
