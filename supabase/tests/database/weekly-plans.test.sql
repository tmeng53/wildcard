-- What the database keeps true about weekly plans however the API writes them.
begin;
select plan(7);

insert into auth.users (id, email) values ('b0000000-0000-0000-0000-000000000001', 'bo@example.com');

select lives_ok(
  $$insert into public.weekly_plans (member_id, week_start, payload)
    values ('b0000000-0000-0000-0000-000000000001', '2026-10-19', '{"version":1}')$$,
  'a plan for a week starting on Monday is saved'
);
select throws_ok(
  $$insert into public.weekly_plans (member_id, week_start, payload)
    values ('b0000000-0000-0000-0000-000000000001', '2026-10-19', '{"version":1}')$$,
  '23505', 'duplicate key value violates unique constraint "weekly_plans_pkey"',
  'a member has one plan a week'
);
select throws_ok(
  $$insert into public.weekly_plans (member_id, week_start, payload)
    values ('b0000000-0000-0000-0000-000000000001', '2026-10-21', '{"version":1}')$$,
  '23514', null, 'a week starts on Monday'
);
select throws_ok(
  $$insert into public.weekly_plans (member_id, week_start, payload)
    values ('b0000000-0000-0000-0000-000000000001', '2026-10-26', '{"days":[]}')$$,
  '23514', null, 'stored plan JSON carries its version'
);

select throws_ok(
  $$insert into public.plan_templates (member_id, from_week, payload)
    values ('b0000000-0000-0000-0000-000000000001', '2026-10-21', '{"version":1}')$$,
  '23514', null, 'a template applies from a Monday'
);

delete from auth.users where id = 'b0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.weekly_plans where member_id = 'b0000000-0000-0000-0000-000000000001'),
  0, 'deleting an account deletes its plans'
);
select is(
  (select count(*)::int from public.plan_templates where member_id = 'b0000000-0000-0000-0000-000000000001'),
  0, 'deleting an account deletes its templates'
);

select * from finish();
rollback;
