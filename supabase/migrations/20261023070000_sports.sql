-- The sports list every picker in the app shows: categories, each sport's names in the app's
-- languages and its icon, and the short lists some screens show first (sign-up's 最常见 and
-- 更多, 练了's quick picks). It is data, served by the API's catalog, so a new sport, name,
-- icon or order needs no app release. Stored check-ins and weekly plans keep a sport by its
-- id, so an id never changes and a sport is never deleted: one the pickers should stop
-- offering is marked `offered = false` and keeps its names for the check-ins that use it.
-- As with every table, only our API reads it; the rows below are the first list.

-- A sport's or category's id: camelCase letters and digits, as the app and the API know it.
create function public.is_catalog_id(id text) returns boolean
language sql immutable
set search_path = ''
as $$ select id ~ '^[a-z][A-Za-z0-9]{0,39}$' $$;

create table public.sport_categories (
  id text primary key check (public.is_catalog_id(id)),
  -- The picker's tabs, in this order.
  position int not null unique check (position > 0),
  name_zh_hans text not null check (name_zh_hans <> ''),
  name_en text not null check (name_en <> ''),
  name_zh_hant text not null check (name_zh_hant <> '')
);

create table public.sports (
  -- `custom` is the wire's word for 其他, a sport the member names themselves.
  id text primary key check (public.is_catalog_id(id) and id <> 'custom'),
  category_id text not null references public.sport_categories (id),
  -- Its place in its category.
  position int not null check (position > 0),
  -- An SF Symbol name; the app draws a general figure for one its iOS doesn't have.
  icon text not null check (icon ~ '^[a-z0-9]+(\.[a-z0-9]+)*$'),
  name_zh_hans text not null check (name_zh_hans <> ''),
  name_en text not null check (name_en <> ''),
  name_zh_hant text not null check (name_zh_hant <> ''),
  offered boolean not null default true,
  unique (category_id, position) deferrable initially immediate
);

-- A short list a screen shows before the whole list, in order.
create table public.sport_picks (
  list text not null check (list in ('signUpCommon', 'signUpMore', 'checkInQuick')),
  position int not null check (position > 0),
  sport_id text not null references public.sports (id),
  primary key (list, position) deferrable initially immediate,
  unique (list, sport_id)
);

-- A sport keeps its id and is never deleted, since check-ins and plans name it.
create function public.sports_keep_their_ids() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a sport is never deleted; set offered = false' using errcode = '42501';
  end if;
  if new.id <> old.id then
    raise exception 'a sport''s id never changes' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger sports_keep_their_ids
  before update or delete on public.sports
  for each row execute function public.sports_keep_their_ids();

-- A truncate skips the row triggers, so it would wipe the list without a word in the log.
create function public.sport_catalog_no_truncate() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'the sports list changes row by row, so each change is logged' using errcode = '42501';
end;
$$;

create trigger sport_categories_no_truncate
  before truncate on public.sport_categories
  for each statement execute function public.sport_catalog_no_truncate();
create trigger sports_no_truncate
  before truncate on public.sports
  for each statement execute function public.sport_catalog_no_truncate();
create trigger sport_picks_no_truncate
  before truncate on public.sport_picks
  for each statement execute function public.sport_catalog_no_truncate();

-- Every change to the list, however it is made: one row per inserted, changed or deleted
-- row with its full new value (the old one for a delete), and none for an update that
-- changed nothing. Only grows.
create table public.sport_catalog_events (
  id bigint generated always as identity primary key,
  -- The table changed: sport_categories, sports or sport_picks.
  kind text not null,
  op text not null check (op in ('INSERT', 'UPDATE', 'DELETE')),
  value jsonb not null,
  -- The database role that made it.
  by_role text not null default current_user,
  at timestamptz not null default now()
);

create function public.log_sport_catalog_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.sport_catalog_events (kind, op, value)
  values (
    tg_table_name, tg_op,
    case when tg_op = 'DELETE' then pg_catalog.to_jsonb(old) else pg_catalog.to_jsonb(new) end
  );
  return null;
end;
$$;

create trigger sport_categories_logged
  after insert or delete on public.sport_categories
  for each row execute function public.log_sport_catalog_change();
create trigger sport_categories_changes_logged
  after update on public.sport_categories
  for each row when (old is distinct from new) execute function public.log_sport_catalog_change();
create trigger sports_logged
  after insert on public.sports
  for each row execute function public.log_sport_catalog_change();
create trigger sports_changes_logged
  after update on public.sports
  for each row when (old is distinct from new) execute function public.log_sport_catalog_change();
create trigger sport_picks_logged
  after insert or delete on public.sport_picks
  for each row execute function public.log_sport_catalog_change();
create trigger sport_picks_changes_logged
  after update on public.sport_picks
  for each row when (old is distinct from new) execute function public.log_sport_catalog_change();

create function public.sport_catalog_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'sport_catalog_events is append-only' using errcode = '42501';
end;
$$;

create trigger sport_catalog_events_append_only
  before update or delete on public.sport_catalog_events
  for each row execute function public.sport_catalog_events_append_only();
create trigger sport_catalog_events_no_truncate
  before truncate on public.sport_catalog_events
  for each statement execute function public.sport_catalog_events_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.sport_categories enable row level security;
alter table public.sports enable row level security;
alter table public.sport_picks enable row level security;
alter table public.sport_catalog_events enable row level security;

-- The first list ------------------------------------------------------------------

insert into public.sport_categories (id, position, name_zh_hans, name_en, name_zh_hant) values
  ('runWalk', 1, '跑走', 'Run and walk', '跑步健走'),
  ('strength', 2, '力量', 'Strength', '重訓'),
  ('cardio', 3, '有氧和课程', 'Cardio and classes', '有氧和課程'),
  ('mindBody', 4, '身心', 'Mind and body', '身心'),
  ('water', 5, '水上', 'Water', '水上'),
  ('racket', 6, '球拍', 'Racket', '球拍'),
  ('ball', 7, '球类', 'Ball sports', '球類'),
  ('cycling', 8, '骑行', 'Cycling', '單車'),
  ('outdoorWinter', 9, '户外和冬季', 'Outdoor and winter', '戶外和冬季'),
  ('combat', 10, '格斗', 'Combat', '格鬥'),
  ('dance', 11, '舞蹈', 'Dance', '舞蹈'),
  ('everyday', 12, '生活也算练', 'Everyday counts', '生活也算練');

insert into public.sports (id, category_id, position, icon, name_zh_hans, name_en, name_zh_hant) values
  ('run', 'runWalk', 1, 'figure.run', '跑步', 'Run', '跑步'),
  ('walk', 'runWalk', 2, 'figure.walk', '快走', 'Walk', '快走'),
  ('hike', 'runWalk', 3, 'figure.hiking', '徒步', 'Hike', '健行'),
  ('trailRun', 'runWalk', 4, 'figure.run', '越野跑', 'Trail run', '越野跑'),
  ('strength', 'strength', 1, 'figure.strengthtraining.traditional', '力量训练', 'Strength training', '重訓'),
  ('crossfit', 'strength', 2, 'figure.cross.training', 'CrossFit', 'CrossFit', 'CrossFit'),
  ('hyrox', 'strength', 3, 'figure.highintensity.intervaltraining', 'Hyrox', 'Hyrox', 'Hyrox'),
  ('kettlebell', 'strength', 4, 'figure.strengthtraining.traditional', '壶铃', 'Kettlebell', '壺鈴'),
  ('spin', 'cardio', 1, 'figure.indoor.cycle', '动感单车', 'Spin', '飛輪'),
  ('elliptical', 'cardio', 2, 'figure.elliptical', '椭圆机', 'Elliptical', '滑步機'),
  ('rowing', 'cardio', 3, 'figure.rower', '划船机', 'Rowing', '划船機'),
  ('hiit', 'cardio', 4, 'figure.highintensity.intervaltraining', 'HIIT', 'HIIT', 'HIIT'),
  ('jumpRope', 'cardio', 5, 'figure.jumprope', '跳绳', 'Jump rope', '跳繩'),
  ('aerobics', 'cardio', 6, 'figure.step.training', '有氧操', 'Aerobics', '有氧舞蹈'),
  ('yoga', 'mindBody', 1, 'figure.yoga', '瑜伽', 'Yoga', '瑜伽'),
  ('matPilates', 'mindBody', 2, 'figure.pilates', '普拉提垫上', 'Mat Pilates', '墊上皮拉提斯'),
  ('reformerPilates', 'mindBody', 3, 'figure.pilates', '普拉提器械', 'Reformer Pilates', '器械皮拉提斯'),
  ('barre', 'mindBody', 4, 'figure.barre', 'barre', 'Barre', 'barre'),
  ('stretching', 'mindBody', 5, 'figure.flexibility', '拉伸', 'Stretching', '伸展'),
  ('swim', 'water', 1, 'figure.pool.swim', '游泳', 'Swim', '游泳'),
  ('surf', 'water', 2, 'figure.surfing', '冲浪', 'Surf', '衝浪'),
  ('paddleboard', 'water', 3, 'figure.surfing', '桨板', 'Paddleboard', '立槳'),
  ('kayak', 'water', 4, 'figure.rower', '皮划艇', 'Kayak', '獨木舟'),
  ('tennis', 'racket', 1, 'figure.tennis', '网球', 'Tennis', '網球'),
  ('badminton', 'racket', 2, 'figure.badminton', '羽毛球', 'Badminton', '羽球'),
  ('pickleball', 'racket', 3, 'figure.pickleball', '匹克球', 'Pickleball', '匹克球'),
  ('tableTennis', 'racket', 4, 'figure.table.tennis', '乒乓球', 'Table tennis', '桌球'),
  ('squash', 'racket', 5, 'figure.squash', '壁球', 'Squash', '壁球'),
  ('basketball', 'ball', 1, 'figure.basketball', '篮球', 'Basketball', '籃球'),
  ('soccer', 'ball', 2, 'figure.indoor.soccer', '足球', 'Soccer', '足球'),
  ('volleyball', 'ball', 3, 'figure.volleyball', '排球', 'Volleyball', '排球'),
  ('golf', 'ball', 4, 'figure.golf', '高尔夫', 'Golf', '高爾夫'),
  ('baseballSoftball', 'ball', 5, 'figure.baseball', '棒垒球', 'Baseball and softball', '棒壘球'),
  ('ultimate', 'ball', 6, 'figure.disc.sports', '飞盘', 'Ultimate', '飛盤'),
  ('roadCycling', 'cycling', 1, 'figure.outdoor.cycle', '公路骑行', 'Road cycling', '公路車'),
  ('mountainBiking', 'cycling', 2, 'bicycle', '山地车', 'Mountain biking', '登山車'),
  ('climb', 'outdoorWinter', 1, 'figure.climbing', '攀岩', 'Climb', '攀岩'),
  ('ski', 'outdoorWinter', 2, 'figure.skiing.downhill', '滑雪', 'Ski', '滑雪'),
  ('snowboard', 'outdoorWinter', 3, 'figure.snowboarding', '单板', 'Snowboard', '單板'),
  ('skate', 'outdoorWinter', 4, 'figure.skating', '滑冰', 'Skate', '溜冰'),
  ('boxing', 'combat', 1, 'figure.boxing', '拳击', 'Boxing', '拳擊'),
  ('kickboxing', 'combat', 2, 'figure.kickboxing', '泰拳踢拳', 'Kickboxing', '泰拳踢拳'),
  ('jiuJitsu', 'combat', 3, 'figure.wrestling', '巴西柔术', 'Jiu-jitsu', '巴西柔術'),
  ('martialArts', 'combat', 4, 'figure.martial.arts', '武术', 'Martial arts', '武術'),
  ('dance', 'dance', 1, 'figure.dance', '舞蹈', 'Dance', '舞蹈'),
  ('dogWalk', 'everyday', 1, 'dog.fill', '遛狗', 'Dog walk', '遛狗'),
  ('walkCommute', 'everyday', 2, 'figure.walk', '走路通勤', 'Walk commute', '走路通勤'),
  ('bikeCommute', 'everyday', 3, 'figure.outdoor.cycle', '骑车通勤', 'Bike commute', '騎車通勤'),
  ('deepClean', 'everyday', 4, 'bubbles.and.sparkles.fill', '大扫除', 'Deep clean', '大掃除'),
  ('moving', 'everyday', 5, 'shippingbox.fill', '搬家', 'Moving', '搬家'),
  ('strollerWalk', 'everyday', 6, 'stroller.fill', '带娃散步', 'Stroller walk', '推車散步'),
  ('gardening', 'everyday', 7, 'leaf.fill', '园艺', 'Gardening', '園藝');

insert into public.sport_picks (list, position, sport_id) values
  ('signUpCommon', 1, 'swim'),
  ('signUpCommon', 2, 'run'),
  ('signUpCommon', 3, 'strength'),
  ('signUpCommon', 4, 'tennis'),
  ('signUpCommon', 5, 'climb'),
  ('signUpCommon', 6, 'yoga'),
  ('signUpMore', 1, 'roadCycling'),
  ('signUpMore', 2, 'matPilates'),
  ('signUpMore', 3, 'badminton'),
  ('signUpMore', 4, 'hike'),
  ('signUpMore', 5, 'basketball'),
  ('signUpMore', 6, 'ski'),
  ('signUpMore', 7, 'pickleball'),
  ('signUpMore', 8, 'dance'),
  ('signUpMore', 9, 'boxing'),
  ('signUpMore', 10, 'soccer'),
  ('checkInQuick', 1, 'run'),
  ('checkInQuick', 2, 'strength'),
  ('checkInQuick', 3, 'yoga'),
  ('checkInQuick', 4, 'swim'),
  ('checkInQuick', 5, 'spin'),
  ('checkInQuick', 6, 'hike'),
  ('checkInQuick', 7, 'tennis');
