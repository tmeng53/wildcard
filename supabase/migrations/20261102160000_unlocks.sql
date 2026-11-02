-- What members unlock by training: the character editor's stores (商店街) and props. Each
-- store or prop that isn't a starter has a rule: it opens once the member has posted `after`
-- 练了 check-ins in one of its sports (any sport when `sports` is empty), counting only
-- check-ins made since the rule was added (Tracy, 2026-11-02: check-ins from before unlocking
-- existed don't count). Once unlocked, it stays unlocked. The rules are data, changed through
-- admin tools; the API works out what a member earned and keeps it here.

create table public.unlock_rules (
  kind text not null check (kind in ('store', 'prop')),
  -- The store's or prop's id in the app's art (`deuce`, `racket`).
  item_id text not null check (public.is_catalog_id(item_id)),
  -- Sport ids from the sports list; empty means any sport.
  sports text[] not null default '{}' check (cardinality(sports) <= 20),
  -- How many 练了 check-ins in those sports open it.
  after int not null check (after between 1 and 100),
  -- Only check-ins made from then count. Set when the rule is added, never changed.
  counts_from timestamptz not null default now(),
  primary key (kind, item_id)
);

-- A rule is changed in place, never deleted, and keeps the time it counts from.
create function public.unlock_rules_keep_their_start() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'unlock rules are never deleted' using errcode = '42501';
  end if;
  if new.kind <> old.kind or new.item_id <> old.item_id or new.counts_from <> old.counts_from then
    raise exception 'an unlock rule keeps its item and start' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger unlock_rules_keep_their_start
  before update or delete on public.unlock_rules
  for each row execute function public.unlock_rules_keep_their_start();

-- Every change to the rules: one row per added or changed rule with its full new value, and
-- none for an update that changed nothing. Only grows.
create table public.unlock_rule_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  -- The database role that made it.
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_unlock_rule_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.unlock_rule_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger unlock_rules_logged
  after insert on public.unlock_rules
  for each row execute function public.log_unlock_rule_change();
create trigger unlock_rules_changes_logged
  after update on public.unlock_rules
  for each row when (old is distinct from new) execute function public.log_unlock_rule_change();

create function public.unlock_rules_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger unlock_rules_no_truncate
  before truncate on public.unlock_rules
  for each statement execute function public.unlock_rules_append_only();
create trigger unlock_rule_events_append_only
  before update or delete on public.unlock_rule_events
  for each row execute function public.unlock_rules_append_only();
create trigger unlock_rule_events_no_truncate
  before truncate on public.unlock_rule_events
  for each statement execute function public.unlock_rules_append_only();

-- What each member unlocked: one row per store or prop, never changed or removed, so it is its
-- own log. It keeps the rule as it was when earned and either the check-in that earned it (which
-- its author may later delete; the unlock stays) or the admin who gave it.
create table public.member_unlocks (
  member_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  item_id text not null,
  sports text[] not null,
  after int not null,
  -- The check-in that reached `after`, and when it was made (or when it was given).
  check_in_id uuid,
  -- The admin who gave it through the admin tools, when no check-in earned it. Not a foreign
  -- key: the row is never changed, even when that admin's account goes.
  given_by uuid,
  unlocked_at timestamptz not null,
  -- When the API saw it was earned.
  granted_at timestamptz not null default now(),
  primary key (member_id, kind, item_id),
  check ((check_in_id is null) <> (given_by is null)),
  foreign key (kind, item_id) references public.unlock_rules (kind, item_id)
);

create trigger member_unlocks_append_only
  before update or delete on public.member_unlocks
  for each row execute function public.member_log_append_only();
create trigger member_unlocks_no_truncate
  before truncate on public.member_unlocks
  for each statement execute function public.member_log_append_only();

-- Counting a member's 练了 check-ins since a time.
create index check_ins_member_id_trained_created_at_idx
on public.check_ins (member_id, created_at)
where kind = 'trained';

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.unlock_rules enable row level security;
alter table public.unlock_rule_events enable row level security;
alter table public.member_unlocks enable row level security;

-- The first rules (Tracy, 2026-10-23): each store opens after 3 练了 in its sports (HALF MOON
-- after 3 of any sport), each prop on the first 练了 in its sports. WARM-UP, the tumbler and the
-- dumbbell are every member's from the start, so they have none.
insert into public.unlock_rules (kind, item_id, sports, after) values
  ('store', 'lap', '{run,walk}', 3),
  ('store', 'nolook', '{basketball,volleyball}', 3),
  ('store', 'moss', '{hike,trailRun,climb}', 3),
  ('store', 'halfmoon', '{}', 3),
  ('store', 'deuce', '{tennis,pickleball,squash}', 3),
  ('prop', 'racket', '{tennis,squash}', 1),
  ('prop', 'badminton', '{badminton}', 1),
  ('prop', 'pickleball', '{pickleball}', 1),
  ('prop', 'pingpong', '{tableTennis}', 1),
  ('prop', 'kettlebell', '{kettlebell,crossfit,hyrox}', 1),
  ('prop', 'yogamat', '{yoga,matPilates,reformerPilates,barre,stretching}', 1),
  ('prop', 'chalkbag', '{climb}', 1),
  ('prop', 'goggles', '{swim}', 1);
