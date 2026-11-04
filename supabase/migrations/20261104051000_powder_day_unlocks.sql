-- POWDER DAY, the winter store (Tracy, 2026-11-04): four pieces come with the store (the salmon
-- jacket, the rice pants, the helmet and the mackerel boots, so they have no rule); each of the
-- other thirteen opens with the next winter-sport 练了, one piece each, the salmon helmet last.
-- Data like every rule, retuned with put_unlock_rule.
--
-- A limited piece limits when it unlocks, never when it is worn (Tracy, 2026-11-04): a rule may
-- follow a switch, and then counts only 练了 made while it is on; what a member unlocked stays
-- theirs all year. POWDER DAY's follow the winter switch, with the 雪场.
alter table public.unlock_rules add column switch_id text references public.switches (id);

insert into public.unlock_rules (kind, item_id, sports, after, switch_id) values
  ('piece', 'powder-tuna', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 1, 'winter'),
  ('piece', 'powder-ikura', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 2, 'winter'),
  ('piece', 'powder-temaki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 3, 'winter'),
  ('piece', 'powder-nori', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 4, 'winter'),
  ('piece', 'powder-tamago', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 5, 'winter'),
  ('piece', 'powder-scarf', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 6, 'winter'),
  ('piece', 'powder-edamame', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 7, 'winter'),
  ('piece', 'powder-uni', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 8, 'winter'),
  ('piece', 'powder-pants', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 9, 'winter'),
  ('piece', 'powder-ebi', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 10, 'winter'),
  ('piece', 'powder-ebifry', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 11, 'winter'),
  ('piece', 'powder-maki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 12, 'winter'),
  ('piece', 'powder-salmonhelmet', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 13, 'winter');
