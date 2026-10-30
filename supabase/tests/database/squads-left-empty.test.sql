-- A squad goes with the account of its last member; one its last member left stays.
begin;
select plan(6);

insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000001', 'di@example.com'),
  ('d0000000-0000-0000-0000-000000000002', 'ed@example.com'),
  ('d0000000-0000-0000-0000-000000000003', 'fay@example.com');
insert into public.squads (id, name, created_by, invite_code) values
  ('5d000000-0000-0000-0000-000000000001', '早八跑团', 'd0000000-0000-0000-0000-000000000001', 'D7M2QX9P'),
  ('5d000000-0000-0000-0000-000000000002', '夜跑团', 'd0000000-0000-0000-0000-000000000003', 'D8W4ZR2M');
insert into public.squad_members (squad_id, member_id) values
  ('5d000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001'),
  ('5d000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002'),
  ('5d000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003');
insert into public.squad_membership_events (squad_id, member_id, kind) values
  ('5d000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'joined'),
  ('5d000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'joined');
insert into public.squad_events (squad_id, actor_id, kind, name, captain_id) values
  ('5d000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'created', '早八跑团',
   'd0000000-0000-0000-0000-000000000001');
insert into public.squad_scene_picks (squad_id, week_start, scene, picked_by) values
  ('5d000000-0000-0000-0000-000000000001', '2026-10-19', 'gym', 'd0000000-0000-0000-0000-000000000001');
-- Ed sent a check-in to the squad, then left it; it stays Ed's when the squad goes.
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('d1111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000002', current_date, now(),
   'healthyMeal', '{"version":1}');
insert into public.check_in_squads (check_in_id, squad_id, position) values
  ('d1111111-1111-1111-1111-111111111111', '5d000000-0000-0000-0000-000000000001', 1);
delete from public.squad_members
  where squad_id = '5d000000-0000-0000-0000-000000000001' and member_id = 'd0000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from public.squads where id = '5d000000-0000-0000-0000-000000000001'),
  1, 'a member leaving keeps the squad for the one still in it'
);

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.squads where id = '5d000000-0000-0000-0000-000000000001'),
  0, 'deleting the last member''s account deletes the squad'
);
select is(
  (select count(*)::int from public.squad_membership_events where squad_id = '5d000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.squad_events where squad_id = '5d000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.squad_scene_picks where squad_id = '5d000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.check_in_squads where squad_id = '5d000000-0000-0000-0000-000000000001'),
  0, 'and its logs, scene picks and the check-ins'' audience with it'
);
select is(
  (select count(*)::int from public.check_ins where id = 'd1111111-1111-1111-1111-111111111111'),
  1, 'a check-in a former member sent to it stays theirs'
);

-- The last member leaving ends the squad but keeps it.
delete from public.squad_members
  where squad_id = '5d000000-0000-0000-0000-000000000002' and member_id = 'd0000000-0000-0000-0000-000000000003';
select is(
  (select count(*)::int from public.squads where id = '5d000000-0000-0000-0000-000000000002'),
  1, 'a squad its last member left stays'
);
delete from auth.users where id = 'd0000000-0000-0000-0000-000000000003';
select is(
  (select count(*)::int from public.squads where id = '5d000000-0000-0000-0000-000000000002'),
  1, 'and stays when that former member deletes their account later'
);

select * from finish();
rollback;
