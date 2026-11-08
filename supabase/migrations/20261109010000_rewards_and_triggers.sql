-- One model for everything a member can get (Tracy, 2026-11-08: "每一个礼品和徽章这些都是有 trigger
-- condition 的"). A reward is a store, a prop or a piece; each says how it is got through its
-- triggers, one row per way, and each member's grants say what they got, through which way, from
-- whom. This replaces the tables kept per source: `unlock_rules` (now `training` triggers),
-- `gift_pieces` (now `coach` triggers), `member_unlocks` and `coach_gifts` (now `grants`) and
-- `coach_gift_opens` (now `grant_opens`), with their rows and logs moved over.
--
-- The ways today:
--   training  the member's 练了 check-ins in its sports, `after` of them, counted from when the
--             trigger was added (and only while its store's and piece's switches were on);
--   coach     a squad's AI coach may give it (a piece; with the description its model reads), at
--             most one a member a week, whoever gives it;
--   team      only the Wildcard team gives it, through admin tools; no coach or rule ever does.
-- Admins may also give what has a training trigger (give_unlocks, a broadcast's gifts): that grant
-- is `team` too. A member holds each reward once, whichever way they got it.
--
-- The log rows moved from `unlock_rule_events` and `gift_piece_events` keep their values as they
-- were (`kind`/`item_id`, `piece_id`), tagged with `replaces`: replaying the log maps them by it.

-- What a member can get, by kind and id. A row is added when its first trigger is, and is never
-- changed or removed, so it is its own log.
create table public.rewards (
  kind text not null check (kind in ('store', 'prop', 'piece')),
  id text not null check (
    case kind
      when 'piece' then id ~ '^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$' and char_length(id) <= 48
      else public.is_catalog_id(id)
    end
  ),
  added_at timestamptz not null default now(),
  primary key (kind, id)
);

create function public.rewards_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger rewards_append_only
  before update or delete on public.rewards
  for each row execute function public.rewards_append_only();
create trigger rewards_no_truncate
  before truncate on public.rewards
  for each statement execute function public.rewards_append_only();

-- Each way a reward is got: one row per reward and way, changed in place and never deleted
-- (`offered = false` stops a coach or the team giving it; a training trigger always counts).
create table public.reward_triggers (
  reward_kind text not null,
  reward_id text not null,
  kind text not null check (kind in ('training', 'coach', 'team')),
  offered boolean not null default true,
  -- training: sport ids from the sports list (empty for any), how many 练了 open it, and when
  -- counting starts (set when the trigger is added, never changed).
  sports text[] check (cardinality(sports) <= 20),
  after int check (after between 1 and 100),
  counts_from timestamptz,
  -- coach: what the piece is, as the coach's model reads it before giving it.
  description text check (char_length(description) between 1 and 200),
  added_at timestamptz not null default now(),
  primary key (reward_kind, reward_id, kind),
  foreign key (reward_kind, reward_id) references public.rewards (kind, id),
  check (
    case kind
      when 'training' then sports is not null and after is not null and counts_from is not null
        and description is null and offered
      when 'coach' then reward_kind = 'piece' and sports is null and after is null
        and counts_from is null
      else sports is null and after is null and counts_from is null and description is null
    end
  )
);

create function public.reward_triggers_keep_their_start() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a reward''s trigger is never deleted' using errcode = '42501';
  end if;
  if (new.reward_kind, new.reward_id, new.kind, new.added_at)
      is distinct from (old.reward_kind, old.reward_id, old.kind, old.added_at)
    or new.counts_from is distinct from old.counts_from
  then
    raise exception 'a trigger keeps its reward, its way and its start' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger reward_triggers_keep_their_start
  before update or delete on public.reward_triggers
  for each row execute function public.reward_triggers_keep_their_start();
create trigger reward_triggers_no_truncate
  before truncate on public.reward_triggers
  for each statement execute function public.rewards_append_only();

-- Every change to the triggers: one row per added or changed trigger with its full new value, and
-- none for an update that changed nothing. Only grows. It starts with the logs it replaces.
create table public.reward_trigger_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

insert into public.reward_trigger_events (op, value, by_role, at)
select op, value || jsonb_build_object('replaces', source), by_role, at
from (
  select op, value, by_role, at, 'unlock_rule_events' as source, id from public.unlock_rule_events
  union all
  select op, value, by_role, at, 'gift_piece_events', id from public.gift_piece_events
) old
order by at, source, id;

create function public.log_reward_trigger_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.reward_trigger_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger reward_trigger_events_append_only
  before update or delete on public.reward_trigger_events
  for each row execute function public.rewards_append_only();
create trigger reward_trigger_events_no_truncate
  before truncate on public.reward_trigger_events
  for each statement execute function public.rewards_append_only();

-- What each member got: one row per reward, never changed or removed, so it is its own log; it goes
-- with the member's account. It says the way (`via`) and, by way: the rule as it was and the
-- check-in that reached it (training); the coach, its squad, its line and the week it counts for
-- (coach); the admin who gave it (team, or a coach's gift given in the coach's name). The admin is
-- not a foreign key: the row is never changed, even when that admin's account goes.
create table public.grants (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  reward_kind text not null,
  reward_id text not null,
  via text not null check (via in ('training', 'coach', 'team')),
  sports text[],
  after int,
  check_in_id uuid,
  coach_id text references public.coaches (id),
  squad_id uuid,
  line text check (char_length(line) between 1 and 60),
  week_from timestamptz,
  -- A coach's gift: given by the coach on its own, or by an admin in its name.
  given_by text check (given_by in ('coach', 'admin')),
  admin_id uuid,
  -- When it was earned (the check-in's time) or given.
  at timestamptz not null,
  -- When the API kept it.
  granted_at timestamptz not null default now(),
  foreign key (reward_kind, reward_id) references public.rewards (kind, id),
  unique (member_id, reward_kind, reward_id),
  check (
    case via
      when 'training' then check_in_id is not null and sports is not null and after is not null
        and coach_id is null and squad_id is null and admin_id is null and given_by is null
      when 'coach' then coach_id is not null and squad_id is not null and given_by is not null
        and check_in_id is null and reward_kind = 'piece'
      else admin_id is not null and check_in_id is null and coach_id is null and squad_id is null
        and week_from is null and given_by is null
    end
  )
);

-- One coach's gift a member a week, whoever gives it.
create unique index grants_one_coach_gift_a_week on public.grants (member_id, week_from)
where via = 'coach';

-- When the member opened a coach's gift (拆开), and whether they put it on then. Once a grant; it
-- goes only with its grant.
create table public.grant_opens (
  grant_id bigint primary key references public.grants (id) on delete cascade,
  worn boolean not null,
  at timestamptz not null default now()
);

create function public.grant_opens_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.grants where id = old.grant_id) then
    return old;
  end if;
  raise exception 'grant_opens is append-only' using errcode = '42501';
end;
$$;

-- The rows move over before the guards and logs go on, so moving them logs nothing new.
insert into public.rewards (kind, id)
select kind, item_id from public.unlock_rules
union
select 'piece', piece_id from public.gift_pieces;

insert into public.reward_triggers (reward_kind, reward_id, kind, sports, after, counts_from, added_at)
select kind, item_id, 'training', sports, after, counts_from, counts_from from public.unlock_rules;

insert into public.reward_triggers (reward_kind, reward_id, kind, offered, description, added_at)
select 'piece', piece_id, 'coach', offered, description, added_at from public.gift_pieces;

insert into public.grants (
  member_id, reward_kind, reward_id, via, sports, after, check_in_id, admin_id, at, granted_at
)
select member_id, kind, item_id,
  case when check_in_id is null then 'team' else 'training' end,
  sports, after, check_in_id,
  given_by,
  unlocked_at, granted_at
from public.member_unlocks
order by granted_at, member_id, kind, item_id;

insert into public.grants (
  member_id, reward_kind, reward_id, via, coach_id, squad_id, line, week_from, given_by, admin_id,
  at, granted_at
)
select member_id, 'piece', piece_id, 'coach', coach_id, squad_id, line, week_from, given_by,
  admin_id, given_at, given_at
from public.coach_gifts
order by given_at, member_id, piece_id;

insert into public.grant_opens (grant_id, worn, at)
select g.id, o.worn, o.at
from public.coach_gift_opens o
join public.grants g
  on g.member_id = o.member_id and g.reward_kind = 'piece' and g.reward_id = o.piece_id
  and g.via = 'coach';

create trigger reward_triggers_logged
  after insert on public.reward_triggers
  for each row execute function public.log_reward_trigger_change();
create trigger reward_triggers_changes_logged
  after update on public.reward_triggers
  for each row when (old is distinct from new) execute function public.log_reward_trigger_change();

create trigger grants_append_only
  before update or delete on public.grants
  for each row execute function public.member_log_append_only();
create trigger grants_no_truncate
  before truncate on public.grants
  for each statement execute function public.member_log_append_only();
create trigger grant_opens_append_only
  before update or delete on public.grant_opens
  for each row execute function public.grant_opens_append_only();
create trigger grant_opens_no_truncate
  before truncate on public.grant_opens
  for each statement execute function public.rewards_append_only();

-- 商店街's live events follow the new tables: a trigger change is everyone's street, a grant the
-- member's.
create trigger shelf_live_event
  after insert on public.reward_trigger_events
  for each statement execute function public.shelf_live_event_everyone();
create trigger shelf_live_event
  after insert on public.grants
  for each row execute function public.shelf_live_event_member();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.rewards enable row level security;
alter table public.reward_triggers enable row level security;
alter table public.reward_trigger_events enable row level security;
alter table public.grants enable row level security;
alter table public.grant_opens enable row level security;

-- The tables they replace, with their guards and triggers.
drop table public.coach_gift_opens;
drop table public.coach_gifts;
drop table public.gift_piece_events;
drop table public.gift_pieces;
drop table public.member_unlocks;
drop table public.unlock_rule_events;
drop table public.unlock_rules;
drop function public.coach_gifts_append_only();
drop function public.log_gift_piece_change();
drop function public.gift_pieces_keep_their_id();
drop function public.log_unlock_rule_change();
drop function public.unlock_rules_keep_their_start();
