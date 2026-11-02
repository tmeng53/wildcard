-- The logs of a member's own changes only grow, until the account's deletion takes them.
begin;
select plan(16);

insert into auth.users (id, email) values ('c0000000-0000-0000-0000-000000000001', 'cy@example.com');
insert into public.profile_events (member_id, time_zone) values
  ('c0000000-0000-0000-0000-000000000001', 'America/Los_Angeles');
insert into public.weekly_plan_events (member_id, week_start, payload) values
  ('c0000000-0000-0000-0000-000000000001', '2026-10-19', '{"version": 1, "days": []}');
insert into public.push_setting_events (member_id, topic, enabled) values
  ('c0000000-0000-0000-0000-000000000001', 'dailyProgress', false);
insert into public.fuel_goal_events (member_id, week_start, payload) values
  ('c0000000-0000-0000-0000-000000000001', '2026-10-26', '{"version": 1, "goals": []}');
insert into public.plan_templates (member_id, from_week, payload) values
  ('c0000000-0000-0000-0000-000000000001', '2026-10-26', '{"version": 1, "days": []}');

select throws_ok($$update public.profile_events set time_zone = 'America/Toronto'$$, '42501', null, 'the profile log refuses an update');
select throws_ok($$delete from public.profile_events$$, '42501', null, 'the profile log refuses a delete');
select throws_ok($$truncate public.profile_events$$, '42501', null, 'the profile log refuses a truncate');
select throws_ok($$update public.weekly_plan_events set week_start = '2026-10-26'$$, '42501', null, 'the plan log refuses an update');
select throws_ok($$delete from public.weekly_plan_events$$, '42501', null, 'the plan log refuses a delete');
select throws_ok($$truncate public.weekly_plan_events$$, '42501', null, 'the plan log refuses a truncate');
select throws_ok($$update public.push_setting_events set enabled = true$$, '42501', null, 'the push settings log refuses an update');
select throws_ok($$delete from public.push_setting_events$$, '42501', null, 'the push settings log refuses a delete');
select throws_ok($$truncate public.push_setting_events$$, '42501', null, 'the push settings log refuses a truncate');
select throws_ok($$update public.fuel_goal_events set week_start = '2026-11-02'$$, '42501', null, 'the 饮食小目标 log refuses an update');
select throws_ok($$delete from public.fuel_goal_events$$, '42501', null, 'the 饮食小目标 log refuses a delete');
select throws_ok($$truncate public.fuel_goal_events$$, '42501', null, 'the 饮食小目标 log refuses a truncate');
select throws_ok($$update public.plan_templates set from_week = '2026-11-02'$$, '42501', null, 'the template log refuses an update');
select throws_ok($$delete from public.plan_templates$$, '42501', null, 'the template log refuses a delete');
select throws_ok($$truncate public.plan_templates$$, '42501', null, 'the template log refuses a truncate');

delete from auth.users where id = 'c0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.profile_events where member_id = 'c0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.weekly_plan_events where member_id = 'c0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.push_setting_events where member_id = 'c0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.fuel_goal_events where member_id = 'c0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.plan_templates where member_id = 'c0000000-0000-0000-0000-000000000001'),
  0, 'deleting an account takes its profile, plan, push settings, 饮食小目标 and template logs with it'
);

select * from finish();
rollback;
