-- Every check-in goes to at least one squad. The check runs at commit, which a test
-- never reaches, so each case makes it run at the end of its statement instead.
begin;
select plan(2);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001');

set constraints public.check_ins_have_audience immediate;

select throws_ok(
  $$insert into public.check_ins (id, member_id, day, kind, payload, version) values
    (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', current_date, 'healthyMeal', '{"slot":"dinner"}', 1)$$,
  '23514', 'a check-in goes to at least one squad', 'a check-in sent to no squad can''t be saved'
);
select lives_ok(
  $$with saved as (
      insert into public.check_ins (id, member_id, day, kind, payload, version) values
        (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', current_date, 'healthyMeal', '{"slot":"dinner"}', 1)
      returning id
    )
    insert into public.check_in_squads (check_in_id, squad_id, position)
    select id, '5a000000-0000-0000-0000-000000000001', 1 from saved$$,
  'a check-in saved with its audience passes'
);

select * from finish();
rollback;
