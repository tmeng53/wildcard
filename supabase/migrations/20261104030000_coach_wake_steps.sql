-- How a coach worked on each wake (Tracy, 2026-11-03): every tool call of a run, in order, with
-- its arguments and what the tool answered, for the admins to read back. Kept in our own
-- database, never sent to the model's provider. A read's answer is kept by its length only, since
-- it holds members' words kept elsewhere; a change's answer is the tool's short reply.
create table public.coach_wake_steps (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- The wake's check-in or comment going takes the steps with it, as it takes the wake.
  wake_id bigint not null references public.coach_wakes (id) on delete cascade,
  step integer not null check (step >= 1),
  tool text not null check (char_length(tool) between 1 and 40),
  input jsonb not null,
  output text not null check (char_length(output) <= 2000),
  at timestamptz not null default now()
);

create index coach_wake_steps_by_wake on public.coach_wake_steps (wake_id, id);

-- The coach's logs, now with steps: a row is never changed or removed, except by the cascade of
-- a squad's end, a check-in's deletion, a comment's deletion, an account's deletion, or (for a
-- step, the only row with `step`) its wake's.
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
  -- A step (only it has `step`) goes with its wake.
  if tg_op = 'DELETE' and to_jsonb(old) ? 'step'
    and not exists (select 1 from public.coach_wakes where id = (to_jsonb(old) ->> 'wake_id')::bigint) then
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

create trigger coach_wake_steps_append_only
  before update or delete on public.coach_wake_steps
  for each row execute function public.coach_log_append_only();
create trigger coach_wake_steps_no_truncate
  before truncate on public.coach_wake_steps
  for each statement execute function public.settings_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_wake_steps enable row level security;
