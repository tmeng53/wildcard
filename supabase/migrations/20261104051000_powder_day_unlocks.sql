-- POWDER DAY, the winter store (Tracy, 2026-11-04): four pieces come with the store (the salmon
-- jacket, the rice pants, the helmet and the mackerel boots, so they have no rule); each of the
-- other thirteen opens with the next winter-sport 练了, one piece each, the salmon helmet last.
-- Data like every rule, retuned with put_unlock_rule.
--
-- A limited piece limits when it unlocks, never when it is worn (Tracy, 2026-11-04): any rule may
-- have a window of days every year, `MM-DD` in New York, both included (the end may be before the
-- start, over New Year), and then counts only 练了 made in it; what a member unlocked stays theirs
-- all year. A window is plain data, set with put_unlock_rule, for any limited piece.
alter table public.unlock_rules
  add column window_start text check (window_start ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  add column window_end text check (window_end ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  add constraint unlock_rules_window_whole check ((window_start is null) = (window_end is null));

insert into public.unlock_rules (kind, item_id, sports, after, window_start, window_end) values
  ('piece', 'powder-tuna', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 1, '11-15', '03-31'),
  ('piece', 'powder-ikura', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 2, '11-15', '03-31'),
  ('piece', 'powder-temaki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 3, '11-15', '03-31'),
  ('piece', 'powder-nori', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 4, '11-15', '03-31'),
  ('piece', 'powder-tamago', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 5, '11-15', '03-31'),
  ('piece', 'powder-scarf', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 6, '11-15', '03-31'),
  ('piece', 'powder-edamame', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 7, '11-15', '03-31'),
  ('piece', 'powder-uni', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 8, '11-15', '03-31'),
  ('piece', 'powder-pants', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 9, '11-15', '03-31'),
  ('piece', 'powder-ebi', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 10, '11-15', '03-31'),
  ('piece', 'powder-ebifry', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 11, '11-15', '03-31'),
  ('piece', 'powder-maki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 12, '11-15', '03-31'),
  ('piece', 'powder-salmonhelmet', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 13, '11-15', '03-31');
