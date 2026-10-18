-- Every check-in goes to at least one squad, from saving it until it is deleted. The
-- check runs at commit, which a test never reaches, so it runs at each statement here.
begin;
select plan(5);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');

set constraints public.check_ins_have_audience, public.check_in_squads_keep_audience immediate;

select throws_ok(
  $$insert into public.check_ins (id, member_id, day, kind, payload, version) values
    (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', current_date, 'healthyMeal', '{"slot":"dinner"}', 1)$$,
  '23514', 'a check-in goes to at least one squad', 'a check-in sent to no squad can''t be saved'
);
select lives_ok(
  $$with saved as (
      insert into public.check_ins (id, member_id, day, kind, payload, version) values
        ('22222222-2222-2222-2222-222222222222', 'b0000000-0000-0000-0000-000000000002', current_date, 'healthyMeal', '{"slot":"dinner"}', 1)
      returning id
    )
    insert into public.check_in_squads (check_in_id, squad_id, position)
    select id, '5a000000-0000-0000-0000-000000000001', 1 from saved$$,
  'a check-in saved with its audience passes'
);

-- Not even the service role takes a check-in's last squad away.
set local role service_role;
select throws_ok(
  $$delete from public.check_in_squads where check_in_id = '22222222-2222-2222-2222-222222222222'$$,
  '23514', 'a check-in goes to at least one squad', 'a check-in''s audience can''t be emptied'
);
set local role postgres;

-- The squad's creator deleting their account leaves Bo's check-in its audience.
delete from auth.users where id = 'a0000000-0000-0000-0000-000000000001';
select results_eq(
  $$select squad_id::text from public.check_in_squads where check_in_id = '22222222-2222-2222-2222-222222222222'$$,
  array['5a000000-0000-0000-0000-000000000001'],
  'a check-in keeps its audience when the squad''s creator deletes their account'
);

-- Deleting the check-in takes its audience with it.
select lives_ok(
  $$delete from public.check_ins where id = '22222222-2222-2222-2222-222222222222'$$,
  'deleting a check-in deletes its audience'
);

select * from finish();
rollback;
