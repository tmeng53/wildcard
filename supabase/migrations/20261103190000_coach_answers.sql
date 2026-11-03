-- Replying to the coach (Tracy, 2026-11-03): a member who can see a post may reply to what its
-- squad's coach said there, and the coach answers each such reply once, as soon as it is
-- written, with no limit on the rounds.

-- A comment may reply to the coach instead of to a member: the coach's id. Never both.
alter table public.check_in_comments
  add column reply_to_coach text references public.coaches (id),
  add constraint check_in_comments_one_reply_to check (reply_to is null or reply_to_coach is null);

-- A comment is still never changed: the one change allowed stays the `reply_to` an account's
-- deletion clears.
create or replace function public.check_in_comments_unchanged()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id = old.id
    and new.check_in_id = old.check_in_id
    and new.member_id = old.member_id
    and new.text = old.text
    and new.commented_at = old.commented_at
    and new.reply_to_coach is not distinct from old.reply_to_coach
    and new.reply_to is null
    and old.reply_to is not null
    and not exists (select 1 from auth.users where id = old.reply_to)
  then
    return new;
  end if;
  raise exception '% can''t be changed', tg_table_name using errcode = '42501';
end;
$$;

-- A wake for a member's reply to the coach: its comment, and the check-in it is under.
alter table public.coach_wakes
  drop constraint coach_wakes_reason_check,
  add constraint coach_wakes_reason_check check (reason in ('checkIn', 'daily', 'comment')),
  drop constraint coach_wakes_check,
  add constraint coach_wakes_check_in_check
    check ((reason in ('checkIn', 'comment')) = (check_in_id is not null)),
  add column comment_id uuid references public.check_in_comments (id) on delete cascade,
  add constraint coach_wakes_comment_check check ((reason = 'comment') = (comment_id is not null));

create unique index coach_wakes_one_per_comment on public.coach_wakes (squad_id, comment_id)
  where reason = 'comment';

-- What a coach answers a member's reply to it: one line, shown under that reply with the 教练
-- tag. At most one a squad a reply, never changed. The squad's end, the check-in's deletion, or
-- the reply's (its writer deleting it, or their account going) takes it.
create table public.coach_answers (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  comment_id uuid not null references public.check_in_comments (id) on delete cascade,
  coach_id text not null references public.coaches (id),
  -- As long as the coach's reply to a check-in may be.
  text text not null check (char_length(text) between 1 and 100),
  wake_id bigint references public.coach_wakes (id) on delete set null,
  at timestamptz not null default now(),
  unique (squad_id, comment_id)
);

create index coach_answers_by_check_in on public.coach_answers (squad_id, check_in_id);

-- The coach's logs, now with answers: a row is never changed or removed, except by the cascade
-- of a squad's end, a check-in's deletion, a comment's deletion (for an answer to it) or an
-- account's deletion (the wake a row points to may go, too).
create or replace function public.coach_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  -- A member's page (only coach_files has `member_id`) goes with the member.
  if tg_op = 'DELETE' and to_jsonb(old) ->> 'member_id' is not null
    and not exists (select 1 from auth.users where id = (to_jsonb(old) ->> 'member_id')::uuid) then
    return old;
  end if;
  -- A reply or an answer (only they have `check_in_id`) goes with its check-in.
  if tg_op = 'DELETE' and to_jsonb(old) ->> 'check_in_id' is not null
    and not exists (select 1 from public.check_ins where id = (to_jsonb(old) ->> 'check_in_id')::uuid) then
    return old;
  end if;
  -- An answer (only it has `comment_id`) goes with the reply it answers.
  if tg_op = 'DELETE' and to_jsonb(old) ->> 'comment_id' is not null
    and not exists (
      select 1 from public.check_in_comments where id = (to_jsonb(old) ->> 'comment_id')::uuid
    ) then
    return old;
  end if;
  -- The wake a row points to may go (its check-in or comment did), and the reference with it;
  -- and a deleted account's id leaves the log's `changed_by`. Nothing else ever changes.
  if tg_op = 'UPDATE' and (
    (to_jsonb(old) ->> 'wake_id' is not null and to_jsonb(new) ->> 'wake_id' is null
      and (to_jsonb(new) - 'wake_id') = (to_jsonb(old) - 'wake_id')
      and not exists (select 1 from public.coach_wakes where id = (to_jsonb(old) ->> 'wake_id')::bigint))
    or (to_jsonb(old) ->> 'changed_by' is not null and to_jsonb(new) ->> 'changed_by' is null
      and (to_jsonb(new) - 'changed_by') = (to_jsonb(old) - 'changed_by')
      and not exists (select 1 from auth.users where id = (to_jsonb(old) ->> 'changed_by')::uuid))
  ) then
    return new;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger coach_answers_append_only
  before update or delete on public.coach_answers
  for each row execute function public.coach_log_append_only();
create trigger coach_answers_no_truncate
  before truncate on public.coach_answers
  for each statement execute function public.settings_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_answers enable row level security;
