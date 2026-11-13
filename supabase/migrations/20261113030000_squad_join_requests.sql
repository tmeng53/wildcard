-- 队长批准入队 (Tracy, 2026-11-12): whoever opens a squad's invite waits for the captain's OK,
-- unless the captain turned that off. Each row is one setting of the switch; the newest stands,
-- and a squad with none needs the OK. Never changed: the table is its own log.
create table public.squad_join_approvals (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  required boolean not null,
  -- Null once the setter deletes their account; the squad keeps its setting.
  set_by uuid references auth.users (id) on delete set null,
  set_at timestamptz not null default now()
);

create index squad_join_approvals_squad_idx on public.squad_join_approvals (squad_id, id);
create index squad_join_approvals_set_by_idx on public.squad_join_approvals (set_by);

create function public.squad_join_approvals_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.set_by is null
    and old.set_by is not null
    and not exists (select 1 from auth.users where id = old.set_by)
    and (new.id, new.squad_id, new.required, new.set_at)
      = (old.id, old.squad_id, old.required, old.set_at)
  then
    return new;
  end if;
  raise exception 'squad_join_approvals is append-only' using errcode = '42501';
end;
$$;

create trigger squad_join_approvals_append_only
  before update or delete on public.squad_join_approvals
  for each row execute function public.squad_join_approvals_append_only();

create trigger squad_join_approvals_no_truncate
  before truncate on public.squad_join_approvals
  for each statement execute function public.squad_join_approvals_append_only();

alter table public.squad_join_approvals enable row level security;

-- A member asking to join a squad that needs the captain's OK. Waiting while it has no answer
-- in squad_join_request_answers; a member waits on one squad at a time (the API checks it under
-- the member's lock). Never changed: the table is its own log.
create table public.squad_join_requests (
  id uuid primary key default gen_random_uuid(),
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- What the member wrote the captain with it (备注), if anything; the API checks its length.
  note text check (char_length(note) <= 200),
  asked_at timestamptz not null default now()
);

create index squad_join_requests_squad_idx on public.squad_join_requests (squad_id, asked_at);
create index squad_join_requests_member_idx on public.squad_join_requests (member_id, asked_at);

-- How a request ended, once: the captain approved or declined it, the member withdrew it, or it
-- was cancelled (the member got into a squad another way, or the squad ended).
create table public.squad_join_request_answers (
  request_id uuid primary key references public.squad_join_requests (id) on delete cascade,
  kind text not null check (kind in ('approved', 'declined', 'withdrawn', 'cancelled')),
  -- Null once the one who answered deletes their account.
  actor_id uuid references auth.users (id) on delete set null,
  at timestamptz not null default now()
);

create index squad_join_request_answers_actor_idx on public.squad_join_request_answers (actor_id);

create function public.squad_join_requests_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The account's or the squad's cascade goes through.
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or not exists (select 1 from public.squads where id = old.squad_id)
  ) then
    return old;
  end if;
  raise exception 'squad_join_requests is append-only' using errcode = '42501';
end;
$$;

create function public.squad_join_request_answers_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The request's cascade goes through.
  if tg_op = 'DELETE'
    and not exists (select 1 from public.squad_join_requests where id = old.request_id)
  then
    return old;
  end if;
  -- The one who answered deleted their account: the answer stays without them.
  if tg_op = 'UPDATE'
    and new.actor_id is null
    and old.actor_id is not null
    and not exists (select 1 from auth.users where id = old.actor_id)
    and (new.request_id, new.kind, new.at) = (old.request_id, old.kind, old.at)
  then
    return new;
  end if;
  raise exception 'squad_join_request_answers is append-only' using errcode = '42501';
end;
$$;

create trigger squad_join_requests_append_only
  before update or delete on public.squad_join_requests
  for each row execute function public.squad_join_requests_append_only();

create trigger squad_join_requests_no_truncate
  before truncate on public.squad_join_requests
  for each statement execute function public.squad_join_requests_append_only();

create trigger squad_join_request_answers_append_only
  before update or delete on public.squad_join_request_answers
  for each row execute function public.squad_join_request_answers_append_only();

create trigger squad_join_request_answers_no_truncate
  before truncate on public.squad_join_request_answers
  for each statement execute function public.squad_join_request_answers_append_only();

alter table public.squad_join_requests enable row level security;
alter table public.squad_join_request_answers enable row level security;
