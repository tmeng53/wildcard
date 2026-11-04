-- POWDER DAY, the winter store (Tracy, 2026-11-04): four pieces come with the store (the salmon
-- jacket, the rice pants, the helmet and the mackerel boots, so they have no rule); each of the
-- other thirteen opens with the next winter-sport 练了, one piece each, the salmon helmet last.
-- Data like every rule, retuned with put_unlock_rule.
insert into public.unlock_rules (kind, item_id, sports, after) values
  ('piece', 'powder-tuna', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 1),
  ('piece', 'powder-ikura', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 2),
  ('piece', 'powder-temaki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 3),
  ('piece', 'powder-nori', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 4),
  ('piece', 'powder-tamago', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 5),
  ('piece', 'powder-scarf', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 6),
  ('piece', 'powder-edamame', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 7),
  ('piece', 'powder-uni', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 8),
  ('piece', 'powder-pants', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 9),
  ('piece', 'powder-ebi', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 10),
  ('piece', 'powder-ebifry', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 11),
  ('piece', 'powder-maki', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 12),
  ('piece', 'powder-salmonhelmet', '{ski,snowboard,skate,crossCountrySki,curling,snowHike,snowman,snowballFight}', 13);
