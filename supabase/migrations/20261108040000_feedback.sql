-- 意见反馈: what members write to us from 设置 › 关于 › 意见反馈, each also filed as an issue
-- in our private feedback repository, where agents pick it up.
-- As with every table, only our API reads and writes it.

-- One row per message, its id made by the app so a retry saves it once. Never changed once
-- sent: the table only grows, and is its own log, until the account's deletion takes it.
-- Which kinds exist is the API's to decide, so `kind` is text it checks.
create table public.feedback (
  id uuid primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  body text not null check (char_length(body) between 1 and 1000),
  -- Photo paths in the member's own folder of the photos bucket, at most 3.
  screenshots text[] not null default '{}' check (cardinality(screenshots) <= 3),
  -- The app's version, build, iOS version, device model and language, as the app sent them.
  app jsonb not null,
  at timestamptz not null
);

create index feedback_member_id_at_idx on public.feedback (member_id, at);

create trigger feedback_append_only
  before update or delete on public.feedback
  for each row execute function public.member_log_append_only();

create trigger feedback_no_truncate
  before truncate on public.feedback
  for each statement execute function public.member_log_append_only();

-- The issue each message was filed as, once it was: a message without a row here is still to
-- file, and the jobs try it again. Never changed once written.
create table public.feedback_issues (
  feedback_id uuid primary key references public.feedback (id) on delete cascade,
  number integer not null check (number > 0),
  url text not null,
  at timestamptz not null
);

-- Only the deletion of its message (by the account's) removes a row.
create function public.feedback_issues_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.feedback where id = old.feedback_id) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger feedback_issues_append_only
  before update or delete on public.feedback_issues
  for each row execute function public.feedback_issues_append_only();

create trigger feedback_issues_no_truncate
  before truncate on public.feedback_issues
  for each statement execute function public.feedback_issues_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.feedback enable row level security;
alter table public.feedback_issues enable row level security;
