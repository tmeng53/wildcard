-- Each store's special (Tracy, 2026-11-04: "要特色一点", "这些新作特色款都要锁着"): one fun piece in the
-- store's own sport and style, the last one each store opens, after 30 counted 练了 in its sports
-- (HALF MOON's on any sport, like the rest of the store). Tuned with `put_unlock_rule`.
insert into public.unlock_rules (kind, item_id, sports, after) values
  ('piece', 'lap-baguette', '{run,walk}', 30),
  ('piece', 'nolook-ball', '{basketball,volleyball}', 30),
  ('piece', 'moss-mushroom', '{hike,trailRun,climb}', 30),
  ('piece', 'halfmoon-mintchip', '{}', 30),
  ('piece', 'deuce-ball', '{tennis,pickleball,squash}', 30);
