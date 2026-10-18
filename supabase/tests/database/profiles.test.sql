-- Each member's time zone, which only they see and change.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select lives_ok(
  $$insert into public.profiles (time_zone) values ('America/Los_Angeles')$$,
  'a member saves their time zone'
);
select lives_ok(
  $$update public.profiles set time_zone = 'America/Toronto'$$,
  'a member changes it when they move'
);
select throws_ok(
  $$update public.profiles set time_zone = 'Mars/Olympus_Mons'$$,
  '22023', 'unknown time zone: Mars/Olympus_Mons', 'a time zone Postgres doesn''t know is refused'
);
select throws_ok(
  $$insert into public.profiles (member_id, time_zone) values ('b0000000-0000-0000-0000-000000000002', 'Asia/Shanghai')$$,
  '42501', null, 'a member can''t create someone else''s profile'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
insert into public.profiles (time_zone) values ('Asia/Shanghai');
select results_eq(
  'select time_zone from public.profiles',
  array['Asia/Shanghai'],
  'a member sees only their own profile'
);
update public.profiles set time_zone = 'UTC' where member_id = 'a0000000-0000-0000-0000-000000000001';
select throws_ok(
  'delete from public.profiles', '42501', null, 'a member can''t delete their profile; it goes with the account'
);
select throws_ok(
  $$select set_config('role', 'anon', true); select * from public.profiles$$,
  '42501', null, 'signed out, profiles can''t be read'
);

select set_config('role', 'postgres', true);
select results_eq(
  'select time_zone from public.profiles order by member_id',
  array['America/Toronto', 'Asia/Shanghai'],
  'a member can''t change someone else''s'
);
delete from auth.users where id = 'a0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.profiles), 1, 'the profile goes with the account'
);

select * from finish();
rollback;
