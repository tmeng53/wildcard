-- Squads and membership: only members see a squad and its roster, and nobody adds
-- members directly (that comes with the invite flow).
begin;
select plan(13);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'cy@example.com');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.sign_out() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select lives_ok(
  $$insert into public.squads (id, name) values ('5a000000-0000-0000-0000-000000000001', '早八跑团')$$,
  'a signed-in user creates a squad'
);
select results_eq(
  'select member_id::text from public.squad_members',
  array['a0000000-0000-0000-0000-000000000001'],
  'the creator is the squad''s first member'
);
select lives_ok(
  $$insert into public.squads (name) values ('第二队') returning id$$,
  'creating a squad returns the new row, as the app asks for it'
);
select throws_ok(
  $$insert into public.squads (name, created_by) values ('冒名队', 'b0000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'nobody creates a squad in someone else''s name'
);
select throws_ok(
  $$insert into public.squad_members (squad_id, member_id) values
    ('5a000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'members can''t be added directly'
);
select throws_ok(
  $$insert into public.squads (name) values ('   ')$$,
  '23514', null, 'a squad needs a name'
);

select pg_temp.sign_out();
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');

select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select is_empty('select 1 from public.squads', 'an outsider doesn''t see the squad');
select is_empty('select 1 from public.squad_members', 'an outsider doesn''t see the roster');

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
update public.squads set name = '改名了' where id = '5a000000-0000-0000-0000-000000000001';
select is(
  (select name from public.squads where id = '5a000000-0000-0000-0000-000000000001'),
  '早八跑团', 'only the creator renames the squad'
);
delete from public.squad_members where member_id = 'b0000000-0000-0000-0000-000000000002';
select pg_temp.sign_out();
select results_eq(
  $$select member_id::text from public.squad_members where squad_id = '5a000000-0000-0000-0000-000000000001'$$,
  array['a0000000-0000-0000-0000-000000000001'],
  'a member can leave a squad'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$delete from public.squads where id = '5a000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'squads aren''t deleted, not even by their creator'
);

-- A check-in Ann sent to the squad keeps it from being deleted at all.
insert into public.check_ins (id, day, kind, payload, version) values
  ('11111111-1111-1111-1111-111111111111', current_date, 'healthyMeal', '{"slot":"lunch"}', 1);
insert into public.check_in_squads (check_in_id, squad_id, position) values
  ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001', 1);
select pg_temp.sign_out();
select throws_ok(
  $$delete from public.squads where id = '5a000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'a squad a check-in went to can''t be deleted, which would leave it with no audience'
);

-- The squad outlives its creator's account.
insert into public.squads (id, name, created_by) values
  ('5c000000-0000-0000-0000-000000000003', '留守队', 'b0000000-0000-0000-0000-000000000002');
delete from auth.users where id = 'b0000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.squads where id = '5c000000-0000-0000-0000-000000000003' and created_by is null), 1,
  'a squad stays when its creator deletes their account'
);

select * from finish();
rollback;
