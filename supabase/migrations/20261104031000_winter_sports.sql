-- The winter sports, as Tracy named and added them through the admin tools on 2026-11-04 (so
-- this changes nothing on the hosted database, and gives every other one the same list): 双板滑雪
-- and 单板滑雪 say which board, and five more join 户外和冬季. They are the sports that unlock
-- the winter POWDER DAY store's pieces.
update public.sports set name_zh_hans = '双板滑雪', name_zh_hant = '雙板滑雪' where id = 'ski';
update public.sports set name_zh_hans = '单板滑雪', name_zh_hant = '單板滑雪' where id = 'snowboard';

insert into public.sports (
  id, category_id, position, icon, name_zh_hans, name_en, name_zh_hant,
  short_name_zh_hans, short_name_en, short_name_zh_hant
) values
  ('crossCountrySki', 'outdoorWinter', 5, 'figure.skiing.crosscountry', '越野滑雪', 'Cross-country ski', '越野滑雪', '越野滑雪', 'XC ski', '越野滑雪'),
  ('curling', 'outdoorWinter', 6, 'figure.curling', '冰壶', 'Curling', '冰壺', null, null, null),
  ('snowHike', 'outdoorWinter', 7, 'figure.hiking', '雪地徒步', 'Snow hike', '雪地健行', null, null, null),
  ('snowman', 'outdoorWinter', 8, 'snowflake', '堆雪人', 'Snowman', '堆雪人', null, null, null),
  ('snowballFight', 'outdoorWinter', 9, 'snowflake', '打雪仗', 'Snowball fight', '打雪仗', '打雪仗', 'Snowballs', '打雪仗')
on conflict (id) do nothing;
