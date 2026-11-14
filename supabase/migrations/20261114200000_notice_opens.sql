-- Which notices a member has already opened somewhere else (Tracy, 2026-11-14): a teammate's
-- comment read on the post itself, the coach's note read on the coach page, a push or banner
-- tapped. 通知 shows such a notice as read, and the bell's dot leaves it out, on every phone,
-- however far `notice_reads` has come. A row per notice the first time it is opened, never
-- changed, so the table only grows and is its own log; deleting the account or the notice (its
-- squad's cascade) takes it.
create table public.notice_opens (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  notice_id bigint not null references public.notices (id) on delete cascade,
  at timestamptz not null default now()
);

-- A notice is one member's, so one row each.
create unique index notice_opens_notice_id_key on public.notice_opens (notice_id);
create index notice_opens_member_id_idx on public.notice_opens (member_id);

-- Only the cascade from the account or the notice removes a row.
create function public.notice_opens_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or not exists (select 1 from public.notices where id = old.notice_id)
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger notice_opens_append_only
  before update or delete on public.notice_opens
  for each row execute function public.notice_opens_append_only();

create trigger notice_opens_no_truncate
  before truncate on public.notice_opens
  for each statement execute function public.notice_opens_append_only();

alter table public.notice_opens enable row level security;
