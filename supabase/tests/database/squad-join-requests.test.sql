-- 入队申请: the switch and the requests are their own logs, never changed, and go with the squad
-- or the account they belong to.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001', 'cap@example.com'),
  ('e0000000-0000-0000-0000-000000000002', 'ask@example.com');
insert into public.squads (id, name, created_by, invite_code) values
  ('5e000000-0000-0000-0000-000000000001', '周三不练腿', 'e0000000-0000-0000-0000-000000000001', 'E7M2QX9P');
insert into public.squad_members (squad_id, member_id) values
  ('5e000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001');
insert into public.squad_join_approvals (squad_id, required, set_by) values
  ('5e000000-0000-0000-0000-000000000001', false, 'e0000000-0000-0000-0000-000000000001');
insert into public.squad_join_requests (id, squad_id, member_id, note) values
  ('e1111111-1111-1111-1111-111111111111', '5e000000-0000-0000-0000-000000000001',
   'e0000000-0000-0000-0000-000000000002', '我是小橘');
insert into public.squad_join_request_answers (request_id, kind, actor_id) values
  ('e1111111-1111-1111-1111-111111111111', 'declined', 'e0000000-0000-0000-0000-000000000001');

select throws_ok(
  'update public.squad_join_approvals set required = true', '42501', null,
  'a setting of the switch is never changed'
);
select throws_ok(
  'delete from public.squad_join_approvals', '42501', null, 'nor deleted'
);
select throws_ok(
  $$update public.squad_join_requests set note = '改了'$$, '42501', null,
  'a request is never changed'
);
select throws_ok(
  $$update public.squad_join_request_answers set kind = 'approved'$$, '42501', null,
  'nor its answer'
);
select throws_ok(
  'delete from public.squad_join_request_answers', '42501', null, 'nor is its answer deleted'
);
select throws_ok(
  $$insert into public.squad_join_request_answers (request_id, kind) values
    ('e1111111-1111-1111-1111-111111111111', 'approved')$$,
  '23505', null, 'a request ends once'
);

-- The captain deletes their account: the setting and answer stay, without who made them.
delete from public.squad_members where member_id = 'e0000000-0000-0000-0000-000000000001';
insert into public.squad_members (squad_id, member_id) values
  ('5e000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002');
delete from auth.users where id = 'e0000000-0000-0000-0000-000000000001';
select is(
  (select array[count(*)::int, count(set_by)::int] from public.squad_join_approvals
   where squad_id = '5e000000-0000-0000-0000-000000000001'),
  array[1, 0], 'a deleted captain''s setting stays without them'
);
select is(
  (select actor_id from public.squad_join_request_answers
   where request_id = 'e1111111-1111-1111-1111-111111111111'),
  null, 'and their answer stays without them'
);

-- The asker deletes their account: their requests go with it.
delete from auth.users where id = 'e0000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.squad_join_requests where member_id = 'e0000000-0000-0000-0000-000000000002'),
  0, 'a deleted member''s requests go with them'
);

select * from finish();
rollback;
