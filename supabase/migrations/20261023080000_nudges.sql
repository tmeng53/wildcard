-- Nudges between squadmates: pokes (`poke`, 戳一下) for now. They aren't pushed one by
-- one; the 6pm daily push counts them and names who sent them.
-- As with every table, only our API reads and writes it.

-- One row per nudge, at most one of each kind from one member to another a day (on the
-- sender's clock), so a retry or a second tap saves nothing new. Which kinds exist is the
-- API's to decide, so `kind` is text it checks, not an enum a migration would have to change.
-- A nudge is never changed once sent: the table only grows, and is its own log.
create table public.nudges (
  id bigint generated always as identity primary key,
  from_member_id uuid not null references auth.users (id) on delete cascade,
  to_member_id uuid not null references auth.users (id) on delete cascade,
  squad_id uuid not null references public.squads (id) on delete cascade,
  kind text not null,
  day date not null,
  at timestamptz not null,
  check (from_member_id <> to_member_id),
  unique (from_member_id, to_member_id, kind, day)
);

create index nudges_to_member_id_at_idx on public.nudges (to_member_id, at);

-- Only an account's or a squad's cascade removes a nudge.
create function public.nudges_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.from_member_id)
    or not exists (select 1 from auth.users where id = old.to_member_id)
    or not exists (select 1 from public.squads where id = old.squad_id)
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger nudges_append_only
  before update or delete on public.nudges
  for each row execute function public.nudges_append_only();

create trigger nudges_no_truncate
  before truncate on public.nudges
  for each statement execute function public.nudges_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.nudges enable row level security;
