-- Clothing pieces unlock one at a time (Tracy, 2026-11-03: "都要但是要做解锁服装", hidden until
-- earned "制造神秘感"). A piece with a rule stays locked in its store, even an open one, until its
-- `after`-th counted 练了 in its store's sports; a piece without one (every piece of season 1)
-- comes with its store. Piece ids are the art's, `<store>-<piece>` (`lap-bib`).

alter table public.unlock_rules drop constraint unlock_rules_kind_check;
alter table public.unlock_rules add constraint unlock_rules_kind_check
  check (kind in ('store', 'prop', 'piece'));
alter table public.unlock_rules drop constraint unlock_rules_item_id_check;
alter table public.unlock_rules add constraint unlock_rules_item_id_check check (
  case kind
    when 'piece' then item_id ~ '^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$' and length(item_id) <= 48
    else public.is_catalog_id(item_id)
  end
);

-- Wardrobe round 2's pieces: each store's sports, one piece at a time (the most fun first); WARM-UP's
-- on any sport, since it is everyone's store.
insert into public.unlock_rules (kind, item_id, sports, after) values
  ('piece', 'warmup-headphones', '{}', 2),
  ('piece', 'warmup-stripe', '{}', 4),
  ('piece', 'warmup-beanie', '{}', 6),
  ('piece', 'warmup-overalls', '{}', 9),
  ('piece', 'warmup-hightop', '{}', 12),
  ('piece', 'warmup-raglan', '{}', 15),
  ('piece', 'warmup-long', '{}', 20),
  ('piece', 'lap-bib', '{run,walk}', 5),
  ('piece', 'lap-singlet', '{run,walk}', 7),
  ('piece', 'lap-spikes', '{run,walk}', 10),
  ('piece', 'lap-wind', '{run,walk}', 13),
  ('piece', 'lap-split', '{run,walk}', 16),
  ('piece', 'lap-runcap', '{run,walk}', 20),
  ('piece', 'lap-vest', '{run,walk}', 25),
  ('piece', 'nolook-slides', '{basketball,volleyball}', 5),
  ('piece', 'nolook-tee', '{basketball,volleyball}', 7),
  ('piece', 'nolook-headband', '{basketball,volleyball}', 10),
  ('piece', 'nolook-snap', '{basketball,volleyball}', 13),
  ('piece', 'nolook-mesh', '{basketball,volleyball}', 16),
  ('piece', 'nolook-shooter', '{basketball,volleyball}', 20),
  ('piece', 'moss-puffer', '{hike,trailRun,climb}', 5),
  ('piece', 'moss-flannel', '{hike,trailRun,climb}', 7),
  ('piece', 'moss-sahara', '{hike,trailRun,climb}', 10),
  ('piece', 'moss-boots', '{hike,trailRun,climb}', 13),
  ('piece', 'moss-fleece', '{hike,trailRun,climb}', 16),
  ('piece', 'moss-climb', '{hike,trailRun,climb}', 20),
  ('piece', 'halfmoon-clip', '{}', 5),
  ('piece', 'halfmoon-biker', '{}', 7),
  ('piece', 'halfmoon-tote', '{}', 10),
  ('piece', 'halfmoon-wrap', '{}', 13),
  ('piece', 'halfmoon-wide', '{}', 16),
  ('piece', 'halfmoon-grip', '{}', 20),
  ('piece', 'halfmoon-zip', '{}', 25),
  ('piece', 'deuce-sweater', '{tennis,pickleball,squash}', 5),
  ('piece', 'deuce-dress', '{tennis,pickleball,squash}', 7),
  ('piece', 'deuce-socks', '{tennis,pickleball,squash}', 10),
  ('piece', 'deuce-cable', '{tennis,pickleball,squash}', 13),
  ('piece', 'deuce-terry', '{tennis,pickleball,squash}', 16),
  ('piece', 'deuce-pants', '{tennis,pickleball,squash}', 20);
