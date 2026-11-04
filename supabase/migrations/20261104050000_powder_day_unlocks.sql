-- POWDER DAY, the winter store (Tracy, 2026-11-04): four pieces come with the store (the salmon
-- jacket, the rice pants, the helmet and the mackerel boots, so they have no rule); each of the
-- other thirteen opens with the next winter-sport 练了, one piece each, the salmon helmet last.
-- Data like every rule, retuned with put_unlock_rule.
--
-- A seasonal store limits when its pieces unlock, never when they are worn (Tracy, 2026-11-04): a
-- rule with a season counts only 练了 made inside that scene's window, New York time; what a
-- member unlocked stays theirs all year.
alter table public.unlock_rules add column season text references public.scenes (id);

insert into public.unlock_rules (kind, item_id, sports, after, season) values
  ('piece', 'powder-tuna', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 1, 'ski'),
  ('piece', 'powder-ikura', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 2, 'ski'),
  ('piece', 'powder-temaki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 3, 'ski'),
  ('piece', 'powder-nori', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 4, 'ski'),
  ('piece', 'powder-tamago', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 5, 'ski'),
  ('piece', 'powder-scarf', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 6, 'ski'),
  ('piece', 'powder-edamame', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 7, 'ski'),
  ('piece', 'powder-uni', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 8, 'ski'),
  ('piece', 'powder-pants', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 9, 'ski'),
  ('piece', 'powder-ebi', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 10, 'ski'),
  ('piece', 'powder-ebifry', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 11, 'ski'),
  ('piece', 'powder-maki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 12, 'ski'),
  ('piece', 'powder-salmonhelmet', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 13, 'ski');
