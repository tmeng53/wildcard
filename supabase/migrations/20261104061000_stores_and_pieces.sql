-- Stores and pieces as first-class catalog rows (Tracy, 2026-11-04): whether a store on the
-- character editor's 商店街 is open, and whether a piece of clothing is out, are each their own
-- switch, apart from unlocking. A store or piece follows its switch (`switch_id`, null for always
-- on); a piece never takes its store's. Unlocking (`unlock_rules`) says only how a piece, store
-- or prop is earned. A starter piece needs no earning: it is out for everyone while its store is
-- open and its switch on. What a member unlocked (`member_unlocks`) stays theirs and wearable
-- whatever the switches. The art (racks, badges) ships with the app; these rows say what of it is
-- out. A store or piece keeps its id and is never deleted: `offered = false` retires one.

create table public.stores (
  id text primary key check (public.is_catalog_id(id)),
  -- The 商店街's order.
  position int not null check (position > 0),
  switch_id text references public.switches (id),
  offered boolean not null default true
);

create table public.pieces (
  id text primary key check (id ~ '^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$' and char_length(id) <= 48),
  store_id text not null references public.stores (id),
  slot text not null check (slot in ('top', 'bottom', 'shoes', 'hat', 'acc')),
  starter boolean not null default false,
  switch_id text references public.switches (id),
  offered boolean not null default true
);

create function public.store_catalog_keeps_ids() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a store or piece is never deleted; set offered to false' using errcode = '42501';
  end if;
  if new.id <> old.id then
    raise exception 'a store''s or piece''s id never changes' using errcode = '42501';
  end if;
  return new;
end;
$$;

create function public.store_catalog_no_truncate() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'stores and pieces change row by row, so each change is logged' using errcode = '42501';
end;
$$;

create trigger stores_keep_their_ids
  before update or delete on public.stores
  for each row execute function public.store_catalog_keeps_ids();
create trigger stores_no_truncate
  before truncate on public.stores
  for each statement execute function public.store_catalog_no_truncate();
create trigger pieces_keep_their_ids
  before update or delete on public.pieces
  for each row execute function public.store_catalog_keeps_ids();
create trigger pieces_no_truncate
  before truncate on public.pieces
  for each statement execute function public.store_catalog_no_truncate();

-- Every change to a store or a piece: one row per inserted or changed row with its full new
-- value, and none for an update that changed nothing. Only grow.
create table public.store_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create table public.piece_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_store_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.store_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create function public.log_piece_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.piece_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger stores_logged
  after insert on public.stores
  for each row execute function public.log_store_change();
create trigger stores_changes_logged
  after update on public.stores
  for each row when (old is distinct from new) execute function public.log_store_change();
create trigger pieces_logged
  after insert on public.pieces
  for each row execute function public.log_piece_change();
create trigger pieces_changes_logged
  after update on public.pieces
  for each row when (old is distinct from new) execute function public.log_piece_change();

create function public.store_catalog_log_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger store_events_append_only
  before update or delete on public.store_events
  for each row execute function public.store_catalog_log_append_only();
create trigger store_events_no_truncate
  before truncate on public.store_events
  for each statement execute function public.store_catalog_log_append_only();
create trigger piece_events_append_only
  before update or delete on public.piece_events
  for each row execute function public.store_catalog_log_append_only();
create trigger piece_events_no_truncate
  before truncate on public.piece_events
  for each statement execute function public.store_catalog_log_append_only();

alter table public.stores enable row level security;
alter table public.pieces enable row level security;
alter table public.store_events enable row level security;
alter table public.piece_events enable row level security;

-- The stores and pieces the app's art has today. POWDER DAY is open only while the winter switch
-- is on, with the 雪场; its pieces have no switch of their own.
insert into public.stores (id, position, switch_id) values
  ('warmup', 1, null),
  ('lap', 2, null),
  ('nolook', 3, null),
  ('moss', 4, null),
  ('halfmoon', 5, null),
  ('deuce', 6, null),
  ('powder', 7, 'winter');

insert into public.pieces (id, store_id, slot) values
  ('warmup-tee', 'warmup', 'top'),
  ('warmup-tank', 'warmup', 'top'),
  ('warmup-hoodie', 'warmup', 'top'),
  ('warmup-long', 'warmup', 'top'),
  ('warmup-raglan', 'warmup', 'top'),
  ('warmup-stripe', 'warmup', 'top'),
  ('lap-jacket', 'lap', 'top'),
  ('lap-singlet', 'lap', 'top'),
  ('lap-wind', 'lap', 'top'),
  ('nolook-jersey', 'nolook', 'top'),
  ('nolook-shooter', 'nolook', 'top'),
  ('nolook-tee', 'nolook', 'top'),
  ('nolook-mesh', 'nolook', 'top'),
  ('moss-anorak', 'moss', 'top'),
  ('moss-fleece', 'moss', 'top'),
  ('moss-puffer', 'moss', 'top'),
  ('moss-flannel', 'moss', 'top'),
  ('halfmoon-tank', 'halfmoon', 'top'),
  ('halfmoon-wrap', 'halfmoon', 'top'),
  ('halfmoon-zip', 'halfmoon', 'top'),
  ('deuce-polo', 'deuce', 'top'),
  ('deuce-cable', 'deuce', 'top'),
  ('deuce-dress', 'deuce', 'top'),
  ('powder-salmon', 'powder', 'top'),
  ('powder-tuna', 'powder', 'top'),
  ('powder-tamago', 'powder', 'top'),
  ('powder-ebi', 'powder', 'top'),
  ('powder-maki', 'powder', 'top'),
  ('warmup-shorts', 'warmup', 'bottom'),
  ('warmup-joggers', 'warmup', 'bottom'),
  ('warmup-leggings', 'warmup', 'bottom'),
  ('warmup-overalls', 'warmup', 'bottom'),
  ('lap-pants', 'lap', 'bottom'),
  ('lap-split', 'lap', 'bottom'),
  ('nolook-shorts', 'nolook', 'bottom'),
  ('nolook-snap', 'nolook', 'bottom'),
  ('moss-cargo', 'moss', 'bottom'),
  ('moss-climb', 'moss', 'bottom'),
  ('halfmoon-flare', 'halfmoon', 'bottom'),
  ('halfmoon-biker', 'halfmoon', 'bottom'),
  ('halfmoon-wide', 'halfmoon', 'bottom'),
  ('deuce-shorts', 'deuce', 'bottom'),
  ('deuce-skirt', 'deuce', 'bottom'),
  ('deuce-pants', 'deuce', 'bottom'),
  ('powder-rice', 'powder', 'bottom'),
  ('powder-nori', 'powder', 'bottom'),
  ('powder-pants', 'powder', 'bottom'),
  ('warmup-canvas', 'warmup', 'shoes'),
  ('warmup-runner', 'warmup', 'shoes'),
  ('warmup-hightop', 'warmup', 'shoes'),
  ('lap-runner', 'lap', 'shoes'),
  ('lap-spikes', 'lap', 'shoes'),
  ('nolook-hightop', 'nolook', 'shoes'),
  ('nolook-slides', 'nolook', 'shoes'),
  ('moss-trail', 'moss', 'shoes'),
  ('moss-boots', 'moss', 'shoes'),
  ('halfmoon-studio', 'halfmoon', 'shoes'),
  ('halfmoon-grip', 'halfmoon', 'shoes'),
  ('deuce-court', 'deuce', 'shoes'),
  ('deuce-socks', 'deuce', 'shoes'),
  ('powder-saba', 'powder', 'shoes'),
  ('powder-temaki', 'powder', 'shoes'),
  ('powder-edamame', 'powder', 'shoes'),
  ('powder-ebifry', 'powder', 'shoes'),
  ('warmup-cap', 'warmup', 'hat'),
  ('warmup-headband', 'warmup', 'hat'),
  ('warmup-beanie', 'warmup', 'hat'),
  ('warmup-headphones', 'warmup', 'hat'),
  ('lap-runcap', 'lap', 'hat'),
  ('nolook-backcap', 'nolook', 'hat'),
  ('nolook-headband', 'nolook', 'hat'),
  ('moss-bucket', 'moss', 'hat'),
  ('moss-sahara', 'moss', 'hat'),
  ('halfmoon-clip', 'halfmoon', 'hat'),
  ('deuce-visor', 'deuce', 'hat'),
  ('deuce-terry', 'deuce', 'hat'),
  ('powder-salmonhelmet', 'powder', 'hat'),
  ('powder-ikura', 'powder', 'hat'),
  ('powder-uni', 'powder', 'hat'),
  ('powder-helmet', 'powder', 'hat'),
  ('warmup-towel', 'warmup', 'acc'),
  ('warmup-waistbag', 'warmup', 'acc'),
  ('lap-bib', 'lap', 'acc'),
  ('lap-vest', 'lap', 'acc'),
  ('moss-sling', 'moss', 'acc'),
  ('halfmoon-tied', 'halfmoon', 'acc'),
  ('halfmoon-tote', 'halfmoon', 'acc'),
  ('deuce-sweater', 'deuce', 'acc'),
  ('powder-scarf', 'powder', 'acc');

-- A piece with no rule of its own is a starter: out with its store (WARM-UP's, POWDER DAY's four).
update public.pieces p set starter = true
where not exists (
  select 1 from public.unlock_rules r where r.kind = 'piece' and r.item_id = p.id
);

-- Rules now say only how a piece is earned: the store's switch decides when POWDER DAY's count.
alter table public.unlock_rules drop column switch_id;
