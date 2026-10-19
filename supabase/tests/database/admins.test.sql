-- The admin list and the log of what admins change.
begin;
select plan(5);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'tracy@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'ben@example.com');
insert into public.admins (member_id) values ('a0000000-0000-0000-0000-000000000001');

select lives_ok(
  $$insert into public.admin_actions (admin_id, at, action)
    values ('a0000000-0000-0000-0000-000000000001', now(), '{"version":1,"tool":"turn_off_meme","arguments":{}}')$$,
  'an admin''s change is logged'
);
select throws_ok(
  $$insert into public.admin_actions (admin_id, at, action)
    values ('a0000000-0000-0000-0000-000000000001', now(), '{"tool":"turn_off_meme"}')$$,
  '23514', null, 'a logged action carries its version'
);
select throws_ok(
  $$insert into public.admins (member_id) values ('c0000000-0000-0000-0000-000000000003')$$,
  '23503', null, 'an admin is a real member'
);
delete from auth.users where id = 'a0000000-0000-0000-0000-000000000001';
select results_eq(
  $$select admin_id, action ->> 'tool' from public.admin_actions$$,
  $$values (null::uuid, 'turn_off_meme')$$,
  'an admin can delete their account; their changes stay logged with no one named'
);
insert into public.admins (member_id) values ('b0000000-0000-0000-0000-000000000002');
delete from auth.users where id = 'b0000000-0000-0000-0000-000000000002';
select is_empty(
  $$select 1 from public.admins where member_id = 'b0000000-0000-0000-0000-000000000002'$$,
  'an admin who never changed anything leaves the list when their account is deleted'
);
select * from finish();
rollback;
