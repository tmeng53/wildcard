-- Gifts from a squad's coach (Tracy, 2026-11-04: "教练是可以单独决定去送一些东西的", clothes and
-- things that belong to no store). Only the data and the service for now: the coach decides to
-- give later. A gift is not an unlock by training: it never sits in a store (商店街), and the app
-- shows it apart, in the member's wardrobe.

-- What a coach may give: pieces by their id in the app's art, which no store sells. Changed through
-- admin tools, never deleted (`offered = false` stops new gifts of it; who has one keeps it).
create table public.gift_pieces (
  piece_id text primary key
    check (piece_id ~ '^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$' and length(piece_id) <= 48),
  offered boolean not null default true,
  added_at timestamptz not null default now()
);

create function public.gift_pieces_keep_their_id() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'gift pieces are never deleted' using errcode = '42501';
  end if;
  if new.piece_id <> old.piece_id or new.added_at <> old.added_at then
    raise exception 'a gift piece keeps its id and when it was added' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger gift_pieces_keep_their_id
  before update or delete on public.gift_pieces
  for each row execute function public.gift_pieces_keep_their_id();

-- Every change to the pool: one row per added or changed piece with its full new value, and none
-- for an update that changed nothing. Only grows.
create table public.gift_piece_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_gift_piece_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.gift_piece_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger gift_pieces_logged
  after insert on public.gift_pieces
  for each row execute function public.log_gift_piece_change();
create trigger gift_pieces_changes_logged
  after update on public.gift_pieces
  for each row when (old is distinct from new) execute function public.log_gift_piece_change();

create trigger gift_pieces_no_truncate
  before truncate on public.gift_pieces
  for each statement execute function public.unlock_rules_append_only();
create trigger gift_piece_events_append_only
  before update or delete on public.gift_piece_events
  for each row execute function public.unlock_rules_append_only();
create trigger gift_piece_events_no_truncate
  before truncate on public.gift_piece_events
  for each statement execute function public.unlock_rules_append_only();

-- What each member was given: one row per piece, never changed or removed, so it is its own log.
-- It keeps the coach who gave it and the squad it was coaching. Neither is a foreign key to a row
-- that may go (a squad ends when everyone leaves); coaches are never deleted.
create table public.coach_gifts (
  member_id uuid not null references auth.users (id) on delete cascade,
  piece_id text not null references public.gift_pieces (piece_id),
  coach_id text not null references public.coaches (id),
  squad_id uuid not null,
  given_at timestamptz not null default now(),
  primary key (member_id, piece_id)
);

create trigger coach_gifts_append_only
  before update or delete on public.coach_gifts
  for each row execute function public.member_log_append_only();
create trigger coach_gifts_no_truncate
  before truncate on public.coach_gifts
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.gift_pieces enable row level security;
alter table public.gift_piece_events enable row level security;
alter table public.coach_gifts enable row level security;
