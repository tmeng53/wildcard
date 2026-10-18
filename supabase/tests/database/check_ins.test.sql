-- Check-ins: members write only their own rows, and the payload follows the
-- check-in contract (wire version 1). Which squads see a check-in is in sharing.test.sql.
begin;
select plan(42);

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

-- Photos the check-ins below point at, already uploaded.
insert into storage.objects (bucket_id, name, owner_id) values
  ('check-in-photos', 'a0000000-0000-0000-0000-000000000001/abc.jpg', 'a0000000-0000-0000-0000-000000000001'),
  ('check-in-photos', 'b0000000-0000-0000-0000-000000000002/x.jpg', 'b0000000-0000-0000-0000-000000000002');

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
    ('11111111-1111-1111-1111-111111111111', (now() at time zone 'UTC')::date, now(), 'trained',
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
-- Ann's 练了 moves three days into the past, as if its day had ended.
select pg_temp.sign_out();
update public.check_ins set day = day - 3, created_at = created_at - interval '3 days'
where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
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
-- A check-in counted for today but made 26 hours ago: its day may not be over in UTC-12,
-- but no local day lasts that long.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
insert into public.check_ins (id, day, created_at, kind, payload, version) values
  ('66666666-6666-6666-6666-666666666666',
   ((now() - interval '26 hours') at time zone 'UTC')::date + 1, now() - interval '26 hours',
   'healthyMeal', '{"slot":"breakfast"}', 1);
delete from public.check_ins where id = '66666666-6666-6666-6666-666666666666';
select pg_temp.sign_out();
select isnt_empty(
  $$select 1 from public.check_ins where id = '66666666-6666-6666-6666-666666666666'$$,
  'a check-in can''t be deleted more than 25 hours after it was made'
);


-- The payload follows the contract.
-- Every space and line break Swift's contract knows, as Swift lists them
-- (`CharacterSet.whitespacesAndNewlines`, `Character.isNewline`, swift:6.0 on Linux).
select is(
  (select count(*)::int from regexp_split_to_table(E'\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u200B\u2028\u2029\u202F\u205F\u3000', '') c
   where private.is_short_text(to_jsonb(c), false)),
  0, 'a 免责声明 made only of spaces the contract trims is refused'
);
select is(
  (select count(*)::int from regexp_split_to_table(E'\u000A\u000B\u000C\u000D\u0085\u2028\u2029', '') c
   where private.is_short_text(to_jsonb('腿' || c || '酸'), true)),
  0, 'a caption holding any line break the contract knows is refused'
);
select is(
  (select count(*)::int from regexp_split_to_table(E'\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u200B\u2028\u2029\u202F\u205F\u3000', '') c
   where private.is_short_text(to_jsonb('腿' || c || '酸'), false)),
  26, 'a 免责声明 may hold any of those spaces and line breaks inside'
);
select ok(
  private.is_short_text(to_jsonb(E'\u200B腿酸'::text), true),
  'text may start with a zero-width space, which the app may not trim'
);
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select pg_temp.rejects('trained', '{"sport":"run","minutes":0}', '练了 needs at least 1 minute');
select pg_temp.rejects('disclaimer', '{"text":"\u3000"}', 'a 免责声明 of only an ideographic space is refused');
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
select lives_ok(
  $$insert into public.check_ins (id, day, kind, payload, version) values
    (gen_random_uuid(), current_date, 'disclaimer', '{"text":"腿酸\n明天再练"}', 1)$$,
  'a 免责声明 may span two lines, as the contract allows'
);
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
    (gen_random_uuid(), (now() at time zone 'UTC')::date - 2, now(), 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  '23514', null, 'the local day is within a day of when it was made'
);
select throws_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    (gen_random_uuid(), '2099-01-01', '2099-01-01T00:00:00Z', 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  '23514', null, 'a check-in can''t be dated in the future'
);
select throws_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    (gen_random_uuid(), (now() at time zone 'UTC')::date - 3, now() - interval '3 days', 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  '23514', null, 'a check-in can''t be back-dated beyond the 48-hour offline window'
);
select lives_ok(
  $$insert into public.check_ins (id, day, created_at, received_at, kind, payload, version) values
    ('55555555-5555-5555-5555-555555555555', (now() at time zone 'UTC' - interval '20 hours')::date, now() - interval '20 hours',
     '2000-01-01T00:00:00Z', 'healthyMeal', '{"slot":"lunch"}', 1)$$,
  'a check-in saved offline syncs within 48 hours'
);
select is(
  (select received_at from public.check_ins where id = '55555555-5555-5555-5555-555555555555'),
  now(), 'the server, not the app, sets when it received a check-in'
);
select lives_ok(
  $$insert into public.check_ins (id, day, created_at, kind, payload, version) values
    (gen_random_uuid(), (now() at time zone 'UTC')::date + 1, now(), 'disclaimer', '{"text":"👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦"}', 1)$$,
  'a 免责声明 of 40 family emoji (40 characters in the app, 280 code points) fits, and Kiribati''s tomorrow is allowed'
);
-- A family with skin tones is 1 character in the app but 11 code points.
select ok(
  private.is_short_text(to_jsonb(repeat(
    chr(128104) || chr(127995) || chr(8205) || chr(128105) || chr(127995) || chr(8205)
      || chr(128103) || chr(127995) || chr(8205) || chr(128102) || chr(127995), 40)), true),
  'a caption of 40 families with skin tones (440 code points) fits'
);
select ok(
  not private.is_short_text(to_jsonb(repeat('累', 1001)), false),
  'text over the loose cap of 1000 code points is refused'
);

select * from finish();
rollback;
