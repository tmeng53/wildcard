-- A check-in's log only grows while the post stands; deleting the post, or the account, takes it.
begin;
select plan(6);

insert into auth.users (id, email) values
  ('c3000000-0000-0000-0000-000000000001', 'poster@example.com'),
  ('c3000000-0000-0000-0000-000000000002', 'leaver@example.com');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', current_date, now(),
   'disclaimer', '{"version":1,"text":"下雨了"}'),
  ('c3100000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', current_date, now(),
   'disclaimer', '{"version":1,"text":"腿说它请假"}');
insert into public.check_in_events (check_in_id, member_id, kind, entry)
select id, member_id, 'posted', jsonb_build_object('version', 1, 'payload', payload, 'photos', '[]'::jsonb)
from public.check_ins where id::text like 'c31%';

select throws_ok(
  $$update public.check_in_events set kind = 'edited'$$, '42501', null, 'the check-in log refuses an update'
);
select throws_ok($$delete from public.check_in_events$$, '42501', null, 'the check-in log refuses a delete');
select throws_ok($$truncate public.check_in_events$$, '42501', null, 'the check-in log refuses a truncate');

select lives_ok(
  $$delete from public.check_ins where id = 'c3100000-0000-0000-0000-000000000001'$$, 'a post can be deleted'
);
select is(
  (select count(*)::int from public.check_in_events where check_in_id = 'c3100000-0000-0000-0000-000000000001'),
  0, 'deleting a post takes its log with it'
);
delete from auth.users where id = 'c3000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.check_in_events where member_id = 'c3000000-0000-0000-0000-000000000002'),
  0, 'deleting an account takes its posts'' logs with it'
);

select * from finish();
rollback;
