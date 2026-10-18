-- The app retries a save whenever it can't tell whether the last try landed. Saving
-- the same check-in again succeeds without a second row; reusing its id for something
-- else is refused.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001'),
  ('5b000000-0000-0000-0000-000000000002', '周末队', 'a0000000-0000-0000-0000-000000000001');
insert into storage.objects (bucket_id, name, owner_id) values
  ('check-in-photos', 'a0000000-0000-0000-0000-000000000001/run.jpg', 'a0000000-0000-0000-0000-000000000001'),
  ('check-in-photos', 'a0000000-0000-0000-0000-000000000001/end.jpg', 'a0000000-0000-0000-0000-000000000001');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

-- Ann's 练了 with two photos to two squads, made an hour ago, with fields swapped in.
create function pg_temp.wire(changes jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'day', (now() at time zone 'UTC' - interval '1 hour')::date,
    'createdAt', to_char(now() at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  ) || '{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"a0000000-0000-0000-0000-000000000001","kind":"trained","training":{"sport":"run","minutes":30,"photos":[{"path":"a0000000-0000-0000-0000-000000000001/run.jpg"},{"path":"a0000000-0000-0000-0000-000000000001/end.jpg"}]},"audience":["5b000000-0000-0000-0000-000000000002","5a000000-0000-0000-0000-000000000001"]}'::jsonb || changes;
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select public.create_check_in(pg_temp.wire());
select lives_ok(
  $$select public.create_check_in(pg_temp.wire())$$,
  'saving a check-in with photos again succeeds'
);
select is(
  (select array_agg(check_in) from public.check_ins_wire),
  array[pg_temp.wire()],
  'there is still one check-in, as first saved'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"training":{"sport":"run","minutes":45}}'))$$,
  '23505', 'a different check-in is already saved with this id',
  'the same id with other contents is refused'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"audience":["5a000000-0000-0000-0000-000000000001","5b000000-0000-0000-0000-000000000002"]}'))$$,
  '23505', 'a different check-in is already saved with this id',
  'the same id to the squads in another order is refused'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"day":"2000-01-01"}'))$$,
  '23505', 'a different check-in is already saved with this id',
  'the same id on another day is refused'
);
select lives_ok(
  $$select public.create_check_in(pg_temp.wire(jsonb_build_object('createdAt',
      to_char(now() at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS.MS') || '+00:00')))$$,
  'the same moment written with another UTC offset is still the same check-in'
);

-- 今日免责声明: the retry isn't taken for a second one that day.
select public.create_check_in(pg_temp.wire(
  '{"id":"22222222-2222-2222-2222-222222222222","kind":"disclaimer","disclaimer":{"text":"下雨了"}}'
) - 'training');
select lives_ok(
  $$select public.create_check_in(pg_temp.wire(
      '{"id":"22222222-2222-2222-2222-222222222222","kind":"disclaimer","disclaimer":{"text":"下雨了"}}'
    ) - 'training')$$,
  'saving a 免责声明 again succeeds instead of counting as a second one that day'
);

-- Someone else's check-in id: the caller can't see it, so it's an ordinary insert that
-- fails on the primary key, saying nothing about what that check-in holds.
select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select throws_like(
  $$select public.create_check_in(pg_temp.wire('{"member":"b0000000-0000-0000-0000-000000000002","training":{"sport":"run","minutes":30},"audience":["5a000000-0000-0000-0000-000000000001"]}'))$$,
  '%', 'reusing another member''s id fails'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from public.check_ins), 2, 'retries left no extra rows'
);

select * from finish();
rollback;
