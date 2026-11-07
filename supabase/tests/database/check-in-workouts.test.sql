-- A post's Apple Health workout: posted once per member, gone with its post or its account,
-- and its route or chart kept only with the tile that shows it; a map and a chart each have
-- their own place.
begin;
select plan(10);

insert into auth.users (id, email) values
  ('c4000000-0000-0000-0000-000000000001', 'runner@example.com'),
  ('c4000000-0000-0000-0000-000000000002', 'swimmer@example.com');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('c4100000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', current_date, now(),
   'trained', '{"version":1,"sport":"run","minutes":32}'),
  ('c4100000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000001', current_date, now(),
   'trained', '{"version":1,"sport":"run","minutes":32}'),
  ('c4100000-0000-0000-0000-000000000003', 'c4000000-0000-0000-0000-000000000002', current_date, now(),
   'trained', '{"version":1,"sport":"swim","minutes":40}');

select lives_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary, route, tile_position)
    values ('c4100000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'apple_health',
      'A1', now() - interval '32 minutes', now(), '{"version":1,"durationSec":1920}',
      '{"version":1,"points":[]}', 1)$$,
  'a post keeps its workout'
);
select throws_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary)
    values ('c4100000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000001', 'apple_health',
      'A1', now() - interval '32 minutes', now(), '{"version":1}')$$,
  '23505', null, 'the same workout can''t be posted twice by one member'
);
select throws_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary, route)
    values ('c4100000-0000-0000-0000-000000000003', 'c4000000-0000-0000-0000-000000000002', 'apple_health',
      'S1', now() - interval '40 minutes', now(), '{"version":1}', '{"version":1,"points":[]}')$$,
  '23514', null, 'a route needs the tile that shows it'
);
select throws_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary)
    values ('c4100000-0000-0000-0000-000000000003', 'c4000000-0000-0000-0000-000000000002', 'apple_health',
      'S1', now() - interval '40 minutes', now(), '{"durationSec":2400}')$$,
  '23514', null, 'a summary carries its version'
);
select throws_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary, series, route,
       tile_position)
    values ('c4100000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000001', 'apple_health',
      'A2', now() - interval '32 minutes', now(), '{"version":1}', '{"version":1,"hr":[]}',
      '{"version":1,"points":[]}', 1)$$,
  '23514', null, 'a map with a chart gives the chart its own place'
);
select throws_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary, series, route,
       tile_position, chart_position)
    values ('c4100000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000001', 'apple_health',
      'A2', now() - interval '32 minutes', now(), '{"version":1}', '{"version":1,"hr":[]}',
      '{"version":1,"points":[]}', 2, 2)$$,
  '23514', null, 'the map and the chart don''t share a place'
);
select lives_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary, series, route,
       tile_position, chart_position)
    values ('c4100000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000001', 'apple_health',
      'A2', now() - interval '32 minutes', now(), '{"version":1}', '{"version":1,"hr":[]}',
      '{"version":1,"points":[]}', 1, 5)$$,
  'a workout keeps its map and its chart, each in its place'
);
select lives_ok(
  $$insert into public.check_in_workouts
      (check_in_id, member_id, provider, provider_workout_id, started_at, ended_at, summary)
    values ('c4100000-0000-0000-0000-000000000003', 'c4000000-0000-0000-0000-000000000002', 'apple_health',
      'S1', now() - interval '40 minutes', now(), '{"version":1}')$$,
  'a workout id is unique per member only'
);

delete from public.check_ins where id = 'c4100000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.check_in_workouts where check_in_id = 'c4100000-0000-0000-0000-000000000001'),
  0, 'deleting a post takes its workout with it'
);
delete from auth.users where id = 'c4000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.check_in_workouts where member_id = 'c4000000-0000-0000-0000-000000000002'),
  0, 'deleting an account takes its workouts'
);

select * from finish();
rollback;
