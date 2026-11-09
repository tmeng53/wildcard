-- Thanks for feedback we used (Tracy, 2026-11-08). A member whose bug report we confirmed, or whose
-- idea shipped, gets a thank-you piece, a dedicated badge and a 1-week 高级券. All three are
-- rewards in the one trigger model (`20261109010000_rewards_and_triggers.sql`):
--
--   badge    a dedicated badge (捉虫队, 点子王): the team's own, drawn as a ticket, never one the
--            weekly awards' model picks (those stay in `weekly_award_settings.badges`); a member
--            may hold one many times (×N);
--   voucher  a 高级券 for some days of squad premium, kept until premium exists to redeem it; a
--            member may hold many.
--
-- And one more way to get a reward:
--
--   event    something that happened gives it: today a piece of feedback we adopted
--            (`bug-adopted`, `idea-adopted`). Which rewards each event gives is the triggers'
--            rows, so the mapping is data. Each event gives a reward once per occurrence.
--
-- `feedback_adoptions` records which feedback we used, as what and by whom: only an admin adopts,
-- after checking the bug is real or the idea's PR merged; nothing adopts on its own.

-- Badges and vouchers are rewards too.
alter table public.rewards drop constraint rewards_kind_check;
alter table public.rewards drop constraint rewards_check;
alter table public.rewards add constraint rewards_kind_check
  check (kind in ('store', 'prop', 'piece', 'badge', 'voucher'));
alter table public.rewards add constraint rewards_check check (
  case kind
    when 'store' then public.is_catalog_id(id)
    when 'prop' then public.is_catalog_id(id)
    else id ~ '^[a-z][a-z0-9]*(-[a-z0-9]+){0,3}$' and char_length(id) <= 48
      and (kind <> 'piece' or id ~ '-')
  end
);

-- A badge as the app draws it: its words in each language, its SF Symbol and its colour. Changed in
-- place and logged; never deleted (`offered = false` stops new grants; who has it keeps it).
create table public.badges (
  kind text not null default 'badge' check (kind = 'badge'),
  id text primary key,
  names jsonb not null check (
    coalesce(jsonb_typeof(names -> 'version') = 'number', false)
    and coalesce(char_length(names ->> 'zh-Hans') between 1 and 12, false)
    and coalesce(char_length(names ->> 'zh-Hant') between 1 and 12, false)
    and coalesce(char_length(names ->> 'en') between 1 and 24, false)
  ),
  glyph text not null check (glyph ~ '^[a-z0-9]+(\.[a-z0-9]+)*$' and char_length(glyph) <= 60),
  tone text not null check (tone ~ '^#[0-9A-F]{6}$'),
  offered boolean not null default true,
  added_at timestamptz not null default now(),
  foreign key (kind, id) references public.rewards (kind, id)
);

-- A voucher: how many days of squad premium it is worth once redeemed.
create table public.vouchers (
  kind text not null default 'voucher' check (kind = 'voucher'),
  id text primary key,
  premium_days int not null check (premium_days between 1 and 366),
  offered boolean not null default true,
  added_at timestamptz not null default now(),
  foreign key (kind, id) references public.rewards (kind, id)
);

-- Every change to a badge or voucher: one row per change with its full new value, none for a save
-- that changed nothing. Only grows.
create table public.reward_catalog_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_reward_catalog_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.reward_catalog_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create function public.reward_catalog_keeps_its_id() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a % is never deleted', tg_table_name using errcode = '42501';
  end if;
  if (new.kind, new.id, new.added_at) is distinct from (old.kind, old.id, old.added_at) then
    raise exception 'a % keeps its id', tg_table_name using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger badges_keep_their_id
  before update or delete on public.badges
  for each row execute function public.reward_catalog_keeps_its_id();
create trigger badges_no_truncate
  before truncate on public.badges
  for each statement execute function public.rewards_append_only();
create trigger badges_logged
  after insert on public.badges
  for each row execute function public.log_reward_catalog_change();
create trigger badges_changes_logged
  after update on public.badges
  for each row when (old is distinct from new) execute function public.log_reward_catalog_change();

create trigger vouchers_keep_their_id
  before update or delete on public.vouchers
  for each row execute function public.reward_catalog_keeps_its_id();
create trigger vouchers_no_truncate
  before truncate on public.vouchers
  for each statement execute function public.rewards_append_only();
create trigger vouchers_logged
  after insert on public.vouchers
  for each row execute function public.log_reward_catalog_change();
create trigger vouchers_changes_logged
  after update on public.vouchers
  for each row when (old is distinct from new) execute function public.log_reward_catalog_change();

create trigger reward_catalog_events_append_only
  before update or delete on public.reward_catalog_events
  for each row execute function public.rewards_append_only();
create trigger reward_catalog_events_no_truncate
  before truncate on public.reward_catalog_events
  for each statement execute function public.rewards_append_only();

-- An `event` trigger names the events that give its reward. Training and coaches give only what
-- the wardrobe holds.
alter table public.reward_triggers add column events text[] check (
  cardinality(events) between 1 and 10
  and array_to_string(events, ',') ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*(,[a-z][a-z0-9]*(-[a-z0-9]+)*)*$'
);
alter table public.reward_triggers drop constraint reward_triggers_kind_check;
alter table public.reward_triggers add constraint reward_triggers_kind_check
  check (kind in ('training', 'coach', 'team', 'event'));
alter table public.reward_triggers drop constraint reward_triggers_check;
alter table public.reward_triggers add constraint reward_triggers_check check (
  case kind
    when 'training' then sports is not null and after is not null and counts_from is not null
      and description is null and events is null and offered
      and reward_kind in ('store', 'prop', 'piece')
    when 'coach' then reward_kind = 'piece' and sports is null and after is null
      and counts_from is null and events is null
    when 'event' then events is not null and sports is null and after is null
      and counts_from is null and description is null
      and reward_kind in ('piece', 'badge', 'voucher')
    else sports is null and after is null and counts_from is null and description is null
      and events is null
  end
);

-- A grant by an event names the event and which time it happened (for feedback, its id), so the
-- same feedback never gives twice. A store, prop or piece is still held once; a badge or voucher
-- once per event.
alter table public.grants add column event text;
alter table public.grants add column event_id text check (char_length(event_id) between 1 and 64);
alter table public.grants drop constraint grants_via_check;
alter table public.grants add constraint grants_via_check
  check (via in ('training', 'coach', 'team', 'event'));
alter table public.grants drop constraint grants_check;
alter table public.grants add constraint grants_check check (
  case via
    when 'training' then check_in_id is not null and sports is not null and after is not null
      and coach_id is null and squad_id is null and admin_id is null and given_by is null
      and event is null and event_id is null
    when 'coach' then coach_id is not null and squad_id is not null and given_by is not null
      and check_in_id is null and reward_kind = 'piece' and event is null and event_id is null
    when 'event' then event is not null and event_id is not null and check_in_id is null
      and coach_id is null and squad_id is null and admin_id is null and given_by is null
      and week_from is null and sports is null and after is null
    else admin_id is not null and check_in_id is null and coach_id is null and squad_id is null
      and week_from is null and given_by is null and event is null and event_id is null
  end
);
alter table public.grants drop constraint grants_member_id_reward_kind_reward_id_key;
create unique index grants_held_once on public.grants (member_id, reward_kind, reward_id)
where reward_kind in ('store', 'prop', 'piece');
create unique index grants_once_an_event
  on public.grants (member_id, reward_kind, reward_id, event, event_id)
where via = 'event';

-- Which feedback we used: once a message, as a bug we confirmed or an idea that shipped, and the
-- admin who said so (not a foreign key, so the row stays when their account goes). Never changed;
-- only the message's deletion (by its writer's account) removes it.
create table public.feedback_adoptions (
  feedback_id uuid primary key references public.feedback (id) on delete cascade,
  kind text not null check (kind in ('bug', 'idea')),
  admin_id uuid not null,
  at timestamptz not null default now()
);

create function public.feedback_adoptions_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.feedback where id = old.feedback_id) then
    return old;
  end if;
  raise exception 'feedback_adoptions is append-only' using errcode = '42501';
end;
$$;

create trigger feedback_adoptions_append_only
  before update or delete on public.feedback_adoptions
  for each row execute function public.feedback_adoptions_append_only();
create trigger feedback_adoptions_no_truncate
  before truncate on public.feedback_adoptions
  for each statement execute function public.rewards_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.badges enable row level security;
alter table public.vouchers enable row level security;
alter table public.reward_catalog_events enable row level security;
alter table public.feedback_adoptions enable row level security;
