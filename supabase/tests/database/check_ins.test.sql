-- Check-ins: members write only their own rows, and the payload follows the
-- check-in contract (wire version 1). Which squads see a check-in is in sharing.test.sql.
begin;
select plan(29);

-- Four people: Ann and Bo share a squad, Cy is in a different squad, Di is in none.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'cy@example.com'),
  ('d0000000-0000-0000-0000-000000000004', 'di@example.com');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.sign_out() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

create function pg_temp.rejects(kind text, payload text, description text) returns text language sql as $$
  select throws_ok(
    format('insert into public.check_ins (id, day, kind, payload, version) values (gen_random_uuid(), current_date, %L, %L, 1)', kind, payload),
    '23514', null, description
  );
$$;

-- Ann creates the squad and is its first member through the trigger.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
insert into public.squads (id, name) values ('5a000000-0000-0000-0000-000000000001', '早八跑团');
select pg_temp.sign_out();
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');
insert into public.squads (id, name, created_by) values
  ('5b000000-0000-0000-0000-000000000002', '隔壁队', 'c0000000-0000-0000-0000-000000000003');

-- Each of the three kinds, written by the member as the app sends them.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select lives_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    ('11111111-1111-1111-1111-111111111111', '2025-10-17', '2025-10-18T00:00:00Z', 'trained',
     '{"minutes":45,"photo":{"path":"a0000000-0000-0000-0000-000000000001/abc.jpg"},"sport":"run"}', 1)$$,
  'a member logs 练了 with a photo in their own folder'
);
select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select lives_ok(
  $$insert into public.check_ins (id, day, kind, payload, version) values
    ('22222222-2222-2222-2222-222222222222', current_date, 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  'a member logs 吃得干净'
);
select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select lives_ok(
  $$insert into public.check_ins (id, day, kind, payload, version) values
    ('33333333-3333-3333-3333-333333333333', current_date, 'disclaimer', '{"text":"下雨了，跑道在哭"}', 1)$$,
  'a member logs 今日免责声明'
);

-- Bo sends his to the squad he shares with Ann.
select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
insert into public.check_in_squads (check_in_id, squad_id, position) values
  ('22222222-2222-2222-2222-222222222222', '5a000000-0000-0000-0000-000000000001', 1);

-- Who sees what.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select results_eq(
  'select id::text from public.check_ins order by id',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'],
  'a member sees their own check-ins and those sent to their squad, not another squad''s'
);
select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select results_eq(
  'select id::text from public.check_ins',
  array['33333333-3333-3333-3333-333333333333'],
  'a member of another squad sees only their own'
);
select pg_temp.sign_in('d0000000-0000-0000-0000-000000000004');
select is_empty('select 1 from public.check_ins', 'someone in no squad sees nobody''s check-ins');
select pg_temp.sign_out();
set local role anon;
select throws_ok('select 1 from public.check_ins', '42501', null, 'signed-out callers can''t read check-ins');
select pg_temp.sign_out();

-- Writing as someone else, or changing someone else's rows.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$insert into public.check_ins (id, member_id, day, kind, payload, version) values
    (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000002', current_date, 'healthyMeal', '{"slot":"dinner"}', 1)$$,
  '42501', null, 'a member can''t check in for a squad-mate'
);
delete from public.check_ins where id = '22222222-2222-2222-2222-222222222222';
select pg_temp.sign_out();
select is(
  (select payload from public.check_ins where id = '22222222-2222-2222-2222-222222222222'),
  '{"slot":"lunch"}'::jsonb,
  'a squad-mate''s check-in can''t be deleted by someone else'
);
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$update public.check_ins set member_id = 'b0000000-0000-0000-0000-000000000002'
    where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'a member can''t hand their check-in to someone else'
);
select throws_ok(
  $$update public.check_ins set payload = '{"sport":"run","minutes":50}'
    where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'check-ins can''t be edited, even by their member'
);
delete from public.check_ins where id = '11111111-1111-1111-1111-111111111111';
insert into public.check_ins (id, day, kind, payload, version) values
  ('44444444-4444-4444-4444-444444444444', (now() at time zone 'UTC')::date, 'trained', '{"sport":"yoga","minutes":20}', 1);
delete from public.check_ins where id = '44444444-4444-4444-4444-444444444444';
select pg_temp.sign_out();
select isnt_empty(
  $$select 1 from public.check_ins where id = '11111111-1111-1111-1111-111111111111'$$,
  'a check-in can''t be deleted once its day is over'
);
select is_empty(
  $$select 1 from public.check_ins where id = '44444444-4444-4444-4444-444444444444'$$,
  'a member deletes their own check-in on the same day'
);

-- The payload follows the contract.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select pg_temp.rejects('trained', '{"sport":"run","minutes":0}', '练了 needs at least 1 minute');
select pg_temp.rejects('trained', '{"sport":"run","minutes":601}', '练了 is at most 600 minutes');
select pg_temp.rejects('trained', '{"sport":"run","minutes":30.5}', 'minutes are whole numbers');
select pg_temp.rejects('trained', '{"sport":"sumo","minutes":30}', 'the sport is one the contract names');
select pg_temp.rejects('trained', '{"slot":"lunch"}', 'the payload matches its kind');
select pg_temp.rejects('healthyMeal', '{"slot":"brunch"}', 'the meal is one of the four slots');
select pg_temp.rejects('cheatMeal', '{"caption":"火锅"}', 'a meal names its slot');
select pg_temp.rejects('cheatMeal', '{"slot":"dinner","caption":"火锅\n不后悔"}', 'a caption is one line');
select pg_temp.rejects('trained', '{"sport":"run","minutes":30,"caption":""}', 'a caption isn''t empty');
select pg_temp.rejects('healthyMeal', '{"slot":"lunch","calories":500}', 'no calories or other unknown fields');
select pg_temp.rejects('disclaimer', '{"text":"   "}', 'an empty 免责声明 is rejected');
select pg_temp.rejects('disclaimer', '{"text":" 腿酸 "}', 'the 免责声明 arrives trimmed, as the contract sends it');
select pg_temp.rejects(
  'trained', '{"sport":"run","minutes":30,"photo":{"path":"b0000000-0000-0000-0000-000000000002/x.jpg"}}',
  'a photo must be in the member''s own folder'
);
select throws_ok(
  $$insert into public.check_ins (id, day, kind, payload, version) values
    (gen_random_uuid(), current_date, 'healthyMeal', '{"slot":"lunch"}', 2)$$,
  '23514', null, 'only wire version 1 is stored'
);
select throws_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    (gen_random_uuid(), '2025-10-15', '2025-10-18T00:00:00Z', 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  '23514', null, 'the local day is within a day of when it was made'
);
select lives_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    (gen_random_uuid(), '2025-10-18', '2025-10-17T10:30:00Z', 'disclaimer', '{"text":"🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️🏃‍♀️"}', 1)$$,
  'a 40-emoji 免责声明 (40 characters in the app) fits, and Kiribati''s tomorrow is allowed'
);

select * from finish();
rollback;
