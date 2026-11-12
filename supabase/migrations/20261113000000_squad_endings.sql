-- A squad ends when its last member leaves or is removed (Tracy, 2026-11-12: 解散了的小队 is
-- marked deactivated). It ends once and for good: its invite stops working, nobody joins it
-- again, and nothing runs for it any more (the weekly awards, the coach), so no AI is spent on
-- a squad nobody is in. The squads module writes it in the same transaction as the leave, with
-- an `ended` row in the squad's log; the database keeps it from being undone.

alter table public.squads add column ended_at timestamptz;

alter table public.squad_events drop constraint squad_events_kind_check;
alter table public.squad_events
  add constraint squad_events_kind_check
  check (kind in ('created', 'renamed', 'captainChanged', 'ended'));

-- An ended squad stays ended, at the moment it ended.
create function public.squads_end_once() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.ended_at is not null and new.ended_at is distinct from old.ended_at then
    raise exception 'a squad that ended stays ended' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger squads_end_once
  before update of ended_at on public.squads
  for each row execute function public.squads_end_once();

-- Nobody joins a squad that ended.
create function public.squad_members_not_ended() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.squads where id = new.squad_id and ended_at is not null) then
    raise exception 'the squad ended' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger squad_members_not_ended
  before insert on public.squad_members
  for each row execute function public.squad_members_not_ended();

-- The squads everyone already left end when their last member went (or, with no such row, when
-- they were made), by whom, under the name they had then.
with emptied as (
  select
    squads.id,
    squads.name,
    coalesce(last_out.at, squads.created_at) as at,
    last_out.actor_id
  from public.squads
  left join lateral (
    select events.at, events.actor_id
    from public.squad_membership_events as events
    where events.squad_id = squads.id
    order by events.id desc
    limit 1
  ) as last_out on true
  where squads.ended_at is null
    and not exists (select 1 from public.squad_members where squad_id = squads.id)
),
ended as (
  update public.squads
  set ended_at = emptied.at, captain_id = null
  from emptied
  where squads.id = emptied.id
  returning squads.id
)
insert into public.squad_events (squad_id, actor_id, kind, name, captain_id, at)
select emptied.id, emptied.actor_id, 'ended', emptied.name, null, emptied.at
from emptied
join ended on ended.id = emptied.id;
