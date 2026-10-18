-- Sending a check-in to squads: only members of the squads it was sent to see it,
-- and only its author decides where it goes.
begin;
select plan(11);

-- Ann is in two squads: 早八跑团 with Bo, and 周末队 with Cy.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'cy@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001'),
  ('5b000000-0000-0000-0000-000000000002', '周末队', 'a0000000-0000-0000-0000-000000000001'),
  ('5c000000-0000-0000-0000-000000000003', '隔壁队', 'c0000000-0000-0000-0000-000000000003');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002'),
  ('5b000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.sign_out() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

-- Ann logs three check-ins: one to 早八跑团 only, one to both squads, one not sent yet.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
insert into public.check_ins (id, day, kind, payload, version) values
  ('11111111-1111-1111-1111-111111111111', current_date, 'trained', '{"sport":"run","minutes":30}', 1),
  ('22222222-2222-2222-2222-222222222222', current_date, 'ateClean', '{"slot":"lunch"}', 1),
  ('33333333-3333-3333-3333-333333333333', current_date, 'disclaimer', '{"text":"腿还在酸"}', 1);
select lives_ok(
  $$insert into public.check_in_squads (check_in_id, squad_id) values
    ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001'),
    ('22222222-2222-2222-2222-222222222222', '5a000000-0000-0000-0000-000000000001'),
    ('22222222-2222-2222-2222-222222222222', '5b000000-0000-0000-0000-000000000002')$$,
  'a member sends a check-in to one squad, or to each of their squads'
);
select throws_ok(
  $$insert into public.check_in_squads (check_in_id, squad_id) values
    ('33333333-3333-3333-3333-333333333333', '5c000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'a member can''t send to a squad they aren''t in'
);
select results_eq(
  'select id::text from public.check_ins order by id',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333'],
  'the author sees all of their check-ins, sent or not'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select results_eq(
  'select id::text from public.check_ins order by id',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'],
  'a squad-mate sees what was sent to their squad, not the unsent one'
);
select throws_ok(
  $$insert into public.check_in_squads (check_in_id, squad_id) values
    ('33333333-3333-3333-3333-333333333333', '5a000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a squad-mate can''t send someone else''s check-in'
);
delete from public.check_in_squads where check_in_id = '11111111-1111-1111-1111-111111111111';

select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select results_eq(
  'select id::text from public.check_ins',
  array['22222222-2222-2222-2222-222222222222'],
  'the other squad sees only the check-in sent to every squad'
);
select results_eq(
  'select squad_id::text from public.check_in_squads',
  array['5b000000-0000-0000-0000-000000000002'],
  'members see only where a check-in went among squads they''re in'
);

select pg_temp.sign_out();
select is(
  (select count(*)::int from public.check_in_squads where check_in_id = '11111111-1111-1111-1111-111111111111'),
  1, 'a squad-mate can''t take someone else''s check-in out of a squad'
);

-- Ann takes her 练了 back from 早八跑团.
select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
delete from public.check_in_squads where check_in_id = '11111111-1111-1111-1111-111111111111';
select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select results_eq(
  'select id::text from public.check_ins',
  array['22222222-2222-2222-2222-222222222222'],
  'a check-in the author takes back disappears for the squad'
);

-- Bo leaves 早八跑团, and Ann's check-ins leave his view.
delete from public.squad_members where member_id = 'b0000000-0000-0000-0000-000000000002';
select is_empty('select 1 from public.check_ins', 'someone who left the squad no longer sees its check-ins');

-- When Ann leaves 周末队, her check-in there stops showing to Cy.
select pg_temp.sign_out();
delete from public.squad_members
where squad_id = '5b000000-0000-0000-0000-000000000002' and member_id = 'a0000000-0000-0000-0000-000000000001';
select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select is_empty('select 1 from public.check_ins', 'a member who leaves takes their check-ins out of that squad');

select * from finish();
rollback;
