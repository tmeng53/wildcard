-- Blocking a teammate and reporting what they posted (App Review guideline 1.2; Tracy,
-- 2026-11-20).
--
-- A block is two-way and keeps both in the squad: neither sees the other's posts, comments or
-- reactions, nor gets pushed about them; squad progress still counts both.
--
-- The log is the table: one row per block or unblock, oldest first. A pair's latest row stands.
-- Only grows; deleting either account takes the pair's rows.
create table public.member_blocks (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  other_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('blocked', 'unblocked')),
  at timestamptz not null default now(),
  check (member_id <> other_id)
);

create index member_blocks_member_id_other_id_idx on public.member_blocks (member_id, other_id, id);
create index member_blocks_other_id_member_id_idx on public.member_blocks (other_id, member_id, id);

-- Only the deletion of one of the pair's accounts removes a row.
create function public.member_blocks_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (
    select 1 from auth.users as person
    where person.id = old.member_id
      and exists (select 1 from auth.users as other where other.id = old.other_id)
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger member_blocks_append_only
  before update or delete on public.member_blocks
  for each row execute function public.member_blocks_append_only();

create trigger member_blocks_no_truncate
  before truncate on public.member_blocks
  for each statement execute function public.member_blocks_append_only();

alter table public.member_blocks enable row level security;

-- What a member reported: a teammate's check-in, a comment or a coach's line under a check-in.
-- Never changed, so it is its own log; the reported thing is hidden from the reporter at once,
-- and an admin looks at it from the issue it was filed as (within 24 hours, as the app says).
-- What was said is copied in when it is reported, so the issue shows it even once deleted.
create table public.content_reports (
  id uuid primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('checkIn', 'comment', 'coachReply', 'coachAnswer')),
  check_in_id uuid not null,
  -- The comment, coach reply or coach answer under the check-in; null for the check-in itself.
  item_id text,
  -- Who wrote it, when a member did (null for the coach). Deleting their account takes the
  -- report with what it copied of their words.
  author_id uuid references auth.users (id) on delete cascade,
  -- `{"version": 1, "words": "...", "photos": n}`: what the reporter saw, for the admin.
  snapshot jsonb not null check (coalesce(jsonb_typeof(snapshot -> 'version') = 'number', false)),
  at timestamptz not null default now(),
  check ((kind = 'checkIn') = (item_id is null))
);

create unique index content_reports_once_idx
  on public.content_reports (member_id, kind, check_in_id, coalesce(item_id, ''));
create index content_reports_member_id_idx on public.content_reports (member_id);

-- Only the deletion of the reporter's or the author's account removes a row.
create function public.content_reports_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or (old.author_id is not null and not exists (select 1 from auth.users where id = old.author_id))
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger content_reports_append_only
  before update or delete on public.content_reports
  for each row execute function public.content_reports_append_only();

create trigger content_reports_no_truncate
  before truncate on public.content_reports
  for each statement execute function public.content_reports_append_only();

alter table public.content_reports enable row level security;

-- The issue each report was filed as, in the private feedback repository: a report without a
-- row here is still to file, and the jobs try it again. Never changed once written.
create table public.content_report_issues (
  report_id uuid primary key references public.content_reports (id) on delete cascade,
  number integer not null check (number > 0),
  url text not null,
  at timestamptz not null
);

-- Only the deletion of its report removes a row.
create function public.content_report_issues_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.content_reports where id = old.report_id) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger content_report_issues_append_only
  before update or delete on public.content_report_issues
  for each row execute function public.content_report_issues_append_only();

create trigger content_report_issues_no_truncate
  before truncate on public.content_report_issues
  for each statement execute function public.content_report_issues_append_only();

alter table public.content_report_issues enable row level security;
