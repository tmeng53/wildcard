-- Saving and reading check-ins as the app's wire JSON (ios/Packages/Contracts,
-- version 1), with the squads each one goes to. Also the 3-squad limit.
begin;
select plan(13);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001'),
  ('5b000000-0000-0000-0000-000000000002', '周末队', 'a0000000-0000-0000-0000-000000000001'),
  ('5c000000-0000-0000-0000-000000000003', '隔壁队', 'b0000000-0000-0000-0000-000000000002');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

-- Ann's check-in as the app encodes it, with fields swapped in per case.
create function pg_temp.wire(changes jsonb default '{}') returns jsonb language sql as $$
  select '{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"a0000000-0000-0000-0000-000000000001","day":"2025-10-17","createdAt":"2025-10-18T00:00:00.000Z","kind":"ateClean","meal":{"quality":"cheat","slot":"dinner"},"squads":["5a000000-0000-0000-0000-000000000001","5b000000-0000-0000-0000-000000000002"]}'::jsonb || changes;
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"version":2}'))$$,
  '22023', null, 'only wire version 1 is accepted'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"member":"b0000000-0000-0000-0000-000000000002"}'))$$,
  '42501', null, 'a member can''t save a check-in as someone else'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"squads":[]}'))$$,
  '22023', null, 'a check-in goes to at least one squad'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"squads":["5a000000-0000-0000-0000-000000000001","5a000000-0000-0000-0000-000000000002","5a000000-0000-0000-0000-000000000003","5a000000-0000-0000-0000-000000000004"]}'))$$,
  '22023', null, 'a check-in goes to at most 3 squads'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire('{"squads":["5c000000-0000-0000-0000-000000000003"]}'))$$,
  '42501', null, 'a check-in can''t go to a squad its member isn''t in'
);
select is_empty('select 1 from public.check_ins', 'a refused check-in leaves nothing behind');
select lives_ok(
  $$select public.create_check_in(pg_temp.wire())$$,
  'a member saves a 放纵餐忏悔 to two squads'
);
select is(
  (select check_in from public.check_ins_wire),
  pg_temp.wire(),
  'the author reads it back exactly as the app sent it'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select is(
  (select check_in -> 'squads' from public.check_ins_wire),
  '["5a000000-0000-0000-0000-000000000001"]'::jsonb,
  'a squad-mate sees only their own squad among where it went'
);

-- Postgres's own microsecond timestamps read back in the app's millisecond form.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select public.create_check_in(pg_temp.wire(
  '{"id":"22222222-2222-2222-2222-222222222222","createdAt":"2025-10-17T23:59:59.123456+00:00","kind":"disclaimer","disclaimer":{"text":"腿还在酸"}}'
) - 'meal');
select is(
  (select check_in ->> 'createdAt' from public.check_ins_wire
   where check_in ->> 'id' = '22222222-2222-2222-2222-222222222222'),
  '2025-10-17T23:59:59.123Z',
  'createdAt reads back in UTC with milliseconds'
);

-- At most 3 squads per member.
select lives_ok(
  $$insert into public.squads (name) values ('第三队')$$,
  'a member can be in a third squad'
);
select throws_ok(
  $$insert into public.squads (name) values ('第四队')$$,
  '23514', null, 'a member can''t be in a fourth squad'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from public.squad_members where member_id = 'a0000000-0000-0000-0000-000000000001'),
  3, 'the fourth squad wasn''t created'
);

select * from finish();
rollback;
