-- The daily push's settings: one row, never deleted, and a log that only grows, except that it
-- forgets which admin made a change once that admin deletes their account.
begin;
select plan(12);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000003', 'admin@example.com');
insert into public.daily_push_setting_events (changed_by, settings) values
  ('d0000000-0000-0000-0000-000000000003', '{"version": 1}');

select is((select hour from public.daily_push_settings), 18, 'the daily push starts at 6pm');
select throws_ok($$delete from public.daily_push_settings$$, '42501', null, 'the settings keep their row');
select throws_ok($$insert into public.daily_push_settings (only_row, sending, hour) values (false, true, 9)$$, '23514', null, 'there is only one row of settings');
select throws_ok($$update public.daily_push_settings set hour = 24$$, '23514', null, 'an hour is 0 to 23');
select is(
  (select (plan_reminder_sending, plan_reminder_hour, plan_reminder_minute) from public.daily_push_settings),
  (true, 20, 30), 'the Sunday 去安排下周 push starts on, at 8:30pm'
);
select throws_ok($$update public.daily_push_settings set plan_reminder_minute = 60$$, '23514', null, 'a minute is 0 to 59');

-- 去安排下周 is claimed once a member a week, by that week's Monday.
insert into public.plan_reminder_pushes (member_id, week_start) values ('d0000000-0000-0000-0000-000000000003', '2026-11-09');
select throws_ok($$insert into public.plan_reminder_pushes (member_id, week_start) values ('d0000000-0000-0000-0000-000000000003', '2026-11-09')$$, '23505', null, 'a week is claimed once');
select throws_ok($$insert into public.plan_reminder_pushes (member_id, week_start) values ('d0000000-0000-0000-0000-000000000003', '2026-11-08')$$, '23514', null, 'a week starts on a Monday');

select throws_ok($$update public.daily_push_setting_events set settings = '{"version": 2}'$$, '42501', null, 'the log refuses an update');
select throws_ok($$truncate public.daily_push_setting_events$$, '42501', null, 'the log refuses a truncate');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000003';
select is(
  (select count(*)::int from public.daily_push_setting_events where changed_by is null and settings = '{"version": 1}'),
  1, 'the log keeps the deleted admin''s change, with no one named'
);
select is(
  (select count(*)::int from public.plan_reminder_pushes where member_id = 'd0000000-0000-0000-0000-000000000003'),
  0, 'deleting the account takes its 去安排下周 claims'
);

select * from finish();
rollback;
