-- The notices a member was told, for the bell on 动态 (通知): every push and in-app notice
-- they were sent (the 6pm daily progress, the weekly awards, a teammate moving the squad to
-- another scene, the coach answering their check-in, a store or prop they unlocked), kept
-- forever (Tracy, 2026-11-02), so one missed on the phone can be found again.
-- As with every table, only our API reads and writes it.

-- One row per notice to one member. Which kinds exist is the API's to decide, so `kind` is text
-- it checks, and what each kind is about is `subject` (JSON with a top-level `version`), never a
-- column a migration would have to add. A notice is never changed once written: the table only
-- grows and is its own log; deleting the account (or the squad it was about) takes it.
create table public.notices (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  squad_id uuid references public.squads (id) on delete cascade,
  kind text not null,
  subject jsonb not null,
  at timestamptz not null default now(),
  check (jsonb_typeof(subject) = 'object' and subject ? 'version')
);

create index notices_member_id_id_idx on public.notices (member_id, id desc);

-- Only an account's or a squad's cascade removes a notice.
create function public.notices_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or (old.squad_id is not null and not exists (select 1 from public.squads where id = old.squad_id))
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger notices_append_only
  before update or delete on public.notices
  for each row execute function public.notices_append_only();

create trigger notices_no_truncate
  before truncate on public.notices
  for each statement execute function public.notices_append_only();

alter table public.notices enable row level security;

-- How far each member has read their notices: opening 通知 marks everything up to the newest
-- as seen, which takes the bell's dot away. A row per move forward, never one that doesn't move
-- it; the newest is where they are. Only grows (public.member_log_append_only); deleting the
-- account takes it.
create table public.notice_reads (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  seen_through bigint not null,
  at timestamptz not null default now()
);

create index notice_reads_member_id_id_idx on public.notice_reads (member_id, id desc);

create trigger notice_reads_append_only
  before update or delete on public.notice_reads
  for each row execute function public.member_log_append_only();

create trigger notice_reads_no_truncate
  before truncate on public.notice_reads
  for each statement execute function public.member_log_append_only();

alter table public.notice_reads enable row level security;
