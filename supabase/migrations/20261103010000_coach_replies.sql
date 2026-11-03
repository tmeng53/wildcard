-- What a coach says to a check-in shared to its squad: one line, which the app shows among the
-- post's comments with the 教练 tag, an emoji reaction, or both. At most one a squad a check-in
-- (the check-in's one wake), never changed: the coach's word stands, even after the squad fires
-- it. The squad's end, the check-in's deletion or its author's account deletion takes it.
create table public.coach_replies (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  coach_id text not null references public.coaches (id),
  -- As long as a member's comment may be.
  text text check (char_length(text) between 1 and 100),
  -- One of the coach's emoji (the coach module's list).
  emoji text check (char_length(emoji) between 1 and 16),
  check (text is not null or emoji is not null),
  wake_id bigint references public.coach_wakes (id) on delete set null,
  at timestamptz not null default now(),
  unique (squad_id, check_in_id)
);

-- Files, notes, usage, replies and hires are logs: a row is never changed or removed, except by
-- the cascade of a squad's end, a check-in's deletion (for a reply to it) or an account's deletion
-- (the wake a row points to may go, too).
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
  -- A reply (only coach_replies has `check_in_id`) goes with its check-in.
  if tg_op = 'DELETE' and to_jsonb(old) ->> 'check_in_id' is not null
    and not exists (select 1 from public.check_ins where id = (to_jsonb(old) ->> 'check_in_id')::uuid) then
    return old;
  end if;
  -- The wake a row points to may go (its check-in did), and the reference with it; and a
  -- deleted account's id leaves the log's `changed_by`. Nothing else ever changes.
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

create trigger coach_replies_append_only
  before update or delete on public.coach_replies
  for each row execute function public.coach_log_append_only();
create trigger coach_replies_no_truncate
  before truncate on public.coach_replies
  for each statement execute function public.settings_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_replies enable row level security;
