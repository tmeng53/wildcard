-- What the database keeps true however the API writes: keys, references, uniqueness.
-- Runs as postgres; the API's server role writes the same way.
begin;
select plan(21);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');
insert into public.squads (id, name, created_by, invite_code) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001', 'K7M2QX9P');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');

create function pg_temp.check_in(id uuid, member uuid, kind text, payload text) returns void language sql as $$
  insert into public.check_ins (id, member_id, day, created_at, kind, payload)
  values (id, member, current_date, now(), kind::public.check_in_kind, payload::jsonb);
$$;

-- Saving and retrying.
select lives_ok(
  $$select pg_temp.check_in('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001',
      'trained', '{"version":1,"sport":"run","minutes":30}')$$,
  'a check-in is saved'
);
select throws_ok(
  $$select pg_temp.check_in('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001',
      'trained', '{"version":1,"sport":"run","minutes":30}')$$,
  '23505', 'duplicate key value violates unique constraint "check_ins_pkey"',
  'saving the same id again fails on the primary key, which the API reads as a retry'
);
select throws_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'trained', '{"sport":"run","minutes":30}')$$,
  '23514', null, 'stored check-in JSON carries its version'
);
select throws_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'trained', '{"version":"1"}')$$,
  '23514', null, 'the version is a number'
);
select throws_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'c0000000-0000-0000-0000-000000000003', 'trained', '{"version":1}')$$,
  '23503', null, 'a check-in belongs to a real member'
);

-- One disclaimer a day.
select pg_temp.check_in('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000001',
  'disclaimer', '{"version":1,"text":"下雨了"}');
select throws_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'disclaimer', '{"version":1,"text":"还在下"}')$$,
  '23505', 'duplicate key value violates unique constraint "check_ins_one_disclaimer_a_day"',
  'a second disclaimer on the same day is refused'
);
select lives_ok(
  $$insert into public.check_ins (id, member_id, day, created_at, kind, payload)
    values (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', current_date + 1, now(), 'disclaimer', '{"version":1,"text":"明天"}')$$,
  'the next day gets its own'
);
select lives_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'b0000000-0000-0000-0000-000000000002', 'disclaimer', '{"version":1,"text":"腿酸"}')$$,
  'another member posts theirs the same day'
);
select lives_ok(
  $$select pg_temp.check_in(gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'trained', '{"version":1,"sport":"swim","minutes":20}')$$,
  'other kinds that day are fine'
);

-- Invite codes.
select throws_ok(
  $$insert into public.squads (name, invite_code) values ('夜跑团', 'K7M2QX9P')$$,
  '23505', 'duplicate key value violates unique constraint "squads_invite_code_key"',
  'two squads never share an invite code, which the API reads as "make another"'
);
select throws_ok(
  $$insert into public.squads (name) values ('夜跑团')$$,
  '23502', null, 'every squad has an invite code'
);

-- Audience and photos.
insert into public.check_in_squads (check_in_id, squad_id, position) values
  ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001', 1);
insert into public.check_in_photos (path, check_in_id, position) values
  ('a0000000-0000-0000-0000-000000000001/1.jpg', '11111111-1111-1111-1111-111111111111', 1),
  ('a0000000-0000-0000-0000-000000000001/2.jpg', '11111111-1111-1111-1111-111111111111', 2);
select throws_ok(
  $$insert into public.check_in_photos (path, check_in_id, position) values
    ('a0000000-0000-0000-0000-000000000001/2.jpg', '22222222-2222-2222-2222-222222222222', 1)$$,
  '23505', 'duplicate key value violates unique constraint "check_in_photos_pkey"',
  'a photo belongs to one check-in'
);
select throws_ok(
  $$insert into public.check_in_photos (path, check_in_id, position) values
    ('a0000000-0000-0000-0000-000000000001/3.jpg', '11111111-1111-1111-1111-111111111111', 2)$$,
  '23505', null, 'one photo per position, so there is one cover'
);
select throws_ok(
  $$insert into public.check_in_photos (path, check_in_id, position) values
    ('a0000000-0000-0000-0000-000000000001/4.jpg', '11111111-1111-1111-1111-111111111111', 4)$$,
  '23514', null, 'at most 3 photos'
);
select throws_ok(
  $$insert into public.check_in_squads (check_in_id, squad_id, position) values
    ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001', 2)$$,
  '23505', null, 'a check-in goes to each squad once'
);
select throws_ok(
  $$delete from public.squads where id = '5a000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'a squad a check-in went to can''t be deleted'
);
delete from public.check_ins where id = '11111111-1111-1111-1111-111111111111';
select is(
  (select count(*)::int from public.check_in_photos where check_in_id = '11111111-1111-1111-1111-111111111111'), 0,
  'deleting a check-in frees its photos'
);

-- Time zones and accounts.
select throws_ok(
  $$insert into public.profiles (member_id, time_zone) values ('a0000000-0000-0000-0000-000000000001', 'Mars/Olympus_Mons')$$,
  '22023', 'unknown time zone: Mars/Olympus_Mons', 'a time zone Postgres doesn''t know is refused'
);
select lives_ok(
  $$insert into public.profiles (member_id, time_zone) values ('a0000000-0000-0000-0000-000000000001', 'America/Los_Angeles');
    update public.profiles set time_zone = 'America/Toronto' where member_id = 'a0000000-0000-0000-0000-000000000001'$$,
  'a member''s time zone is saved and changed'
);
select is(
  (select time_zone from public.profiles where member_id = 'a0000000-0000-0000-0000-000000000001'), 'America/Toronto', 'the change is kept'
);
delete from auth.users where id = 'a0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.check_ins where member_id = 'a0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.profiles where member_id = 'a0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.squad_members where member_id = 'a0000000-0000-0000-0000-000000000001'),
  0, 'deleting an account takes its check-ins, profile and memberships with it'
);

select * from finish();
rollback;
