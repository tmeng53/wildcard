-- Each sport category's colour (Tracy, 2026-11-08): the solid colour a 训练's 成绩条, post block,
-- route and chart wear, with white on it. The five scene colours stay with the categories that
-- had them; the rest get their own. Data, so a colour changes through the admin tools
-- (`put_sport_category`) with no app release.
--
-- With it the list is regrouped as Tracy decided the same day: cycling joins 有氧, winter sports
-- get a 冬季 tab of their own (climbing stays under 户外), and every kind of workout Apple Health
-- records has a sport, so a workout imported from it never needs one picked by hand.

alter table public.sport_categories
  add column color text check (color ~ '^#[0-9A-F]{6}$');

-- 冬季, and 户外 for what stays.
insert into public.sport_categories (id, position, name_zh_hans, name_en, name_zh_hant)
values ('winter', 1000, '冬季', 'Winter', '冬季')
on conflict (id) do nothing;
update public.sport_categories
set name_zh_hans = '户外', name_en = 'Outdoor', name_zh_hant = '戶外'
where id = 'outdoorWinter';

-- Moves `ids` (in this order) to the end of `category`, keeping the order they had.
create function pg_temp.move_sports(ids text[], category text) returns void
language sql
as $$
  update public.sports as sport
  set category_id = category,
      position = (
        select coalesce(max(other.position), 0) from public.sports as other
        where other.category_id = category and other.id <> all (ids)
      ) + place.n
  from unnest(ids) with ordinality as place (id, n)
  where sport.id = place.id;
$$;

select pg_temp.move_sports(
  array['ski', 'snowboard', 'crossCountrySki', 'skate', 'curling', 'snowHike', 'snowman', 'snowballFight'],
  'winter'
);
select pg_temp.move_sports(
  array(select id from public.sports where category_id = 'cycling' order by position),
  'cardio'
);
delete from public.sport_categories where id = 'cycling';

-- The tabs in their new order; any added since keep theirs, after these.
update public.sport_categories as category
set position = coalesce(place.position, 100 + category.position)
from public.sport_categories as listed
left join (values
  ('runWalk', 1), ('strength', 2), ('cardio', 3), ('mindBody', 4), ('water', 5), ('racket', 6),
  ('ball', 7), ('outdoorWinter', 8), ('winter', 9), ('combat', 10), ('dance', 11), ('everyday', 12)
) as place (id, position) on place.id = listed.id
where category.id = listed.id;

update public.sport_categories as category
set color = colour.color
from (values
  ('runWalk', '#E65345'), ('cardio', '#C8681C'), ('combat', '#9E2F3A'), ('water', '#079BB8'),
  ('winter', '#2F86C4'), ('strength', '#4A6C8C'), ('racket', '#4F6B22'), ('ball', '#1F8A5B'),
  ('mindBody', '#5E8A7A'), ('dance', '#7B5E96'), ('outdoorWinter', '#8E4A2C'),
  ('everyday', '#6A6A8C')
) as colour (id, color)
where category.id = colour.id;
-- A tab added through the admin tools before this wears the gym's steel until one is picked.
update public.sport_categories set color = '#4A6C8C' where color is null;
alter table public.sport_categories alter column color set not null;

-- Every kind of workout Apple Health records gets a sport (the app maps the rest to these).
insert into public.sports (
  id, category_id, position, icon, name_zh_hans, name_en, name_zh_hant,
  short_name_zh_hans, short_name_en, short_name_zh_hant
)
select
  sport.id, sport.category_id,
  (select coalesce(max(other.position), 0) from public.sports as other where other.category_id = sport.category_id)
    + row_number() over (partition by sport.category_id order by sport.n),
  sport.icon, sport.name_zh_hans, sport.name_en, sport.name_zh_hant,
  case when sport.short_en is not null then sport.name_zh_hans end, sport.short_en,
  case when sport.short_en is not null then sport.name_zh_hant end
from (values
  (1, 'triathlon', 'runWalk', 'figure.run', '铁人三项', 'Triathlon', '鐵人三項', null),
  (2, 'gymnastics', 'strength', 'figure.gymnastics', '体操', 'Gymnastics', '體操', null),
  (3, 'stairs', 'cardio', 'figure.stairs', '爬楼梯', 'Stair climbing', '爬樓梯', 'Stairs'),
  (4, 'fitnessGaming', 'cardio', 'gamecontroller.fill', '体感游戏', 'Fitness games', '體感遊戲', null),
  (5, 'taiChi', 'mindBody', 'figure.taichi', '太极', 'Tai chi', '太極', null),
  (6, 'diving', 'water', 'figure.open.water.swim', '潜水', 'Diving', '潛水', null),
  (7, 'sailing', 'water', 'figure.sailing', '帆船', 'Sailing', '帆船', null),
  (8, 'waterFitness', 'water', 'figure.water.fitness', '水中健身', 'Water fitness', '水中健身', 'Aqua fit'),
  (9, 'waterPolo', 'water', 'figure.waterpolo', '水球', 'Water polo', '水球', null),
  (10, 'waterSports', 'water', 'figure.surfing', '水上运动', 'Water sports', '水上運動', null),
  (11, 'racquetball', 'racket', 'figure.racquetball', '美式壁球', 'Racquetball', '美式壁球', null),
  (12, 'americanFootball', 'ball', 'figure.american.football', '美式橄榄球', 'Football', '美式足球', null),
  (13, 'rugby', 'ball', 'figure.rugby', '橄榄球', 'Rugby', '橄欖球', null),
  (14, 'hockey', 'ball', 'figure.hockey', '冰球', 'Hockey', '冰球', null),
  (15, 'lacrosse', 'ball', 'figure.lacrosse', '长曲棍球', 'Lacrosse', '長曲棍球', null),
  (16, 'cricket', 'ball', 'figure.cricket', '板球', 'Cricket', '板球', null),
  (17, 'handball', 'ball', 'figure.handball', '手球', 'Handball', '手球', null),
  (18, 'bowling', 'ball', 'figure.bowling', '保龄球', 'Bowling', '保齡球', null),
  (19, 'archery', 'outdoorWinter', 'figure.archery', '射箭', 'Archery', '射箭', null),
  (20, 'horseRiding', 'outdoorWinter', 'figure.equestrian.sports', '马术', 'Horse riding', '馬術', 'Riding'),
  (21, 'fishing', 'outdoorWinter', 'figure.fishing', '钓鱼', 'Fishing', '釣魚', null),
  (22, 'hunting', 'outdoorWinter', 'figure.hunting', '狩猎', 'Hunting', '狩獵', null),
  (23, 'fencing', 'combat', 'figure.fencing', '击剑', 'Fencing', '擊劍', null),
  (24, 'wrestling', 'combat', 'figure.wrestling', '摔跤', 'Wrestling', '摔角', null),
  (25, 'play', 'everyday', 'figure.play', '玩耍', 'Play', '玩耍', null)
) as sport (n, id, category_id, icon, name_zh_hans, name_en, name_zh_hant, short_en)
where not exists (select 1 from public.sports as listed where listed.id = sport.id);
