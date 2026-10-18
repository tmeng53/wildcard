-- What a 练了 names (contract `Activity`): one of the 52 listed sports, or the member's
-- own with "sport": "custom" and a 1 to 20 character "customSport".
begin;
select plan(11);

insert into auth.users (id, email) values ('a0000000-0000-0000-0000-000000000001', 'ann@example.com');
select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

create function pg_temp.saves(training text) returns boolean language plpgsql as $$
begin
  insert into public.check_ins (id, day, kind, payload, version)
  values (gen_random_uuid(), current_date, 'trained', training::jsonb, 1);
  return true;
exception when check_violation then
  return false;
end;
$$;

-- Copied from `Sport` in contract PR #14, not from the migration, so a sport dropped
-- from the database fails here.
select is(
  (select count(*)::int from unnest(array[
    'run', 'walk', 'hike', 'trailRun',
    'strength', 'crossfit', 'hyrox', 'kettlebell',
    'spin', 'elliptical', 'rowing', 'hiit', 'jumpRope', 'aerobics',
    'yoga', 'matPilates', 'reformerPilates', 'barre', 'stretching',
    'swim', 'surf', 'paddleboard', 'kayak',
    'tennis', 'badminton', 'pickleball', 'tableTennis', 'squash',
    'basketball', 'soccer', 'volleyball', 'golf', 'baseballSoftball', 'ultimate',
    'roadCycling', 'mountainBiking',
    'climb', 'ski', 'snowboard', 'skate',
    'boxing', 'kickboxing', 'jiuJitsu', 'martialArts',
    'dance',
    'dogWalk', 'walkCommute', 'bikeCommute', 'deepClean', 'moving', 'strollerWalk', 'gardening'
  ]) s where pg_temp.saves(format('{"sport":%s,"minutes":30}', to_jsonb(s)))),
  52, 'every listed sport is accepted'
);
select is(
  (select count(*)::int from unnest(array['pilates', 'cycle', 'ball', 'other', 'Run', 'custom ']) s
   where pg_temp.saves(format('{"sport":%s,"minutes":30}', to_jsonb(s)))),
  0, 'the sports the old list had, and near misses, are refused'
);
select ok(pg_temp.saves('{"sport":"custom","customSport":"飞盘","minutes":30}'), 'a member names their own sport');
select ok(pg_temp.saves('{"sport":"custom","customSport":"陪娃在公园追鸽子追了一下午真的很累啊啊啊","minutes":30}'),
  'a 20-character own sport fits');
select ok(not pg_temp.saves('{"sport":"custom","minutes":30}'), 'an own sport has a name');
select ok(not pg_temp.saves('{"sport":"custom","customSport":"  ","minutes":30}'), 'an own sport''s name isn''t blank');
select ok(not pg_temp.saves('{"sport":"custom","customSport":"飞\n盘","minutes":30}'), 'an own sport''s name is one line');
select ok(not pg_temp.saves('{"sport":"custom","customSport":42,"minutes":30}'), 'an own sport''s name is text');
select ok(not pg_temp.saves('{"sport":null,"minutes":30}'), 'a sport isn''t null');
select ok(not pg_temp.saves('{"sport":"custom","customSport":null,"minutes":30}'), 'an own sport''s name isn''t null');
select ok(not pg_temp.saves('{"sport":"run","customSport":"飞盘","minutes":30}'),
  'only an own sport carries a name');

select * from finish();
rollback;
