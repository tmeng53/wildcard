-- When a squad trained over its weekly goal three finished weeks in a row, its captain is told
-- once, in 通知 and the home's banner, with a higher 人均 N 天 to try (连续 3 周超过小队目标). Each
-- row is one such suggestion: the week whose 战报 froze it (a Monday), the captain told and the
-- days per member suggested. One a squad a week, so the hourly run tells it once. Never changed:
-- the table is its own log.
create table public.squad_goal_suggestions (
  squad_id uuid not null references public.squads (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  -- Null once the captain deletes their account.
  captain_id uuid references auth.users (id) on delete set null,
  days_per_member smallint not null check (days_per_member between 1 and 7),
  suggested_at timestamptz not null default now(),
  primary key (squad_id, week_start)
);

create index squad_goal_suggestions_captain_idx on public.squad_goal_suggestions (captain_id);

create function public.squad_goal_suggestions_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the captain's account deletion clearing who was told, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.captain_id is null
    and old.captain_id is not null
    and not exists (select 1 from auth.users where id = old.captain_id)
    and (new.squad_id, new.week_start, new.days_per_member, new.suggested_at)
      = (old.squad_id, old.week_start, old.days_per_member, old.suggested_at)
  then
    return new;
  end if;
  raise exception 'squad_goal_suggestions is append-only' using errcode = '42501';
end;
$$;

create trigger squad_goal_suggestions_append_only
  before update or delete on public.squad_goal_suggestions
  for each row execute function public.squad_goal_suggestions_append_only();

create trigger squad_goal_suggestions_no_truncate
  before truncate on public.squad_goal_suggestions
  for each statement execute function public.squad_goal_suggestions_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_goal_suggestions enable row level security;
