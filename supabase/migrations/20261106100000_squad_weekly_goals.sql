-- A squad's weekly goal (小队每周目标): the captain sets how many days each member trains on
-- average (人均 N 天, 1 to 7); the squad's goal for a week is that times its members. Each row is
-- one setting and the week it counts from (a Monday); the goal for a week is the newest row from
-- that week or before, and a squad with none uses 3. A squad's first row counts from the week it
-- was made, a captain's change from the next week. Never changed: the table is its own log.
create table public.squad_weekly_goals (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  days_per_member smallint not null check (days_per_member between 1 and 7),
  week_start date not null check (extract(isodow from week_start) = 1),
  -- Null once the setter deletes their account; the squad keeps its goal.
  set_by uuid references auth.users (id) on delete set null,
  set_at timestamptz not null default now()
);

create index squad_weekly_goals_squad_idx on public.squad_weekly_goals (squad_id, week_start, id);
create index squad_weekly_goals_set_by_idx on public.squad_weekly_goals (set_by);

create function public.squad_weekly_goals_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the setter's account deletion clearing who set it, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.set_by is null
    and old.set_by is not null
    and not exists (select 1 from auth.users where id = old.set_by)
    and (new.id, new.squad_id, new.days_per_member, new.week_start, new.set_at)
      = (old.id, old.squad_id, old.days_per_member, old.week_start, old.set_at)
  then
    return new;
  end if;
  raise exception 'squad_weekly_goals is append-only' using errcode = '42501';
end;
$$;

create trigger squad_weekly_goals_append_only
  before update or delete on public.squad_weekly_goals
  for each row execute function public.squad_weekly_goals_append_only();

create trigger squad_weekly_goals_no_truncate
  before truncate on public.squad_weekly_goals
  for each statement execute function public.squad_weekly_goals_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_weekly_goals enable row level security;
