-- The teammate push: its settings (one row, never deleted, a log that only grows), the record of
-- each push handled (one per check-in and member, never changed, gone with the account), and
-- the generation of pushes each phone knows.
begin;
select plan(10);

insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000004', 'admin@example.com'),
  ('d0000000-0000-0000-0000-000000000005', 'member@example.com');
insert into public.teammate_push_setting_events (changed_by, settings) values
  ('d0000000-0000-0000-0000-000000000004', '{"version": 1}');
insert into public.teammate_pushes (check_in_id, member_id, rang, at) values
  ('c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005', true, now());
insert into public.push_devices (token, member_id, environment) values
  ('a1a1', 'd0000000-0000-0000-0000-000000000005', 'sandbox');

select is((select daily_rings from public.teammate_push_settings), 5, 'up to 5 teammate pushes ring a day to begin with');
select throws_ok($$delete from public.teammate_push_settings$$, '42501', null, 'the settings keep their row');
select throws_ok($$update public.teammate_push_settings set daily_rings = 51$$, '23514', null, 'at most 50 ring a day');
select throws_ok($$update public.teammate_push_setting_events set settings = '{"version": 2}'$$, '42501', null, 'the settings log refuses an update');
select throws_ok($$truncate public.teammate_push_setting_events$$, '42501', null, 'the settings log refuses a truncate');

select throws_ok(
  $$insert into public.teammate_pushes (check_in_id, member_id, rang, at) values
    ('c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005', false, now())$$,
  '23505', null, 'a check-in is pushed to a member once');
select throws_ok($$update public.teammate_pushes set rang = false$$, '42501', null, 'a handled push is never changed');
select throws_ok($$delete from public.teammate_pushes$$, '42501', null, 'a handled push is never deleted');

select is((select push_generation::int from public.push_devices where token = 'a1a1'), 1, 'a phone that says nothing knows the first pushes only');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000005';
select is((select count(*)::int from public.teammate_pushes), 0, 'deleting the account takes its handled pushes');

select * from finish();
rollback;
