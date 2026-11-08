-- 意见反馈 only grows, and the account's deletion takes a member's messages and their issues.
begin;
select plan(7);

insert into auth.users (id, email) values ('f0000000-0000-0000-0000-000000000001', 'fay@example.com');
insert into public.feedback (id, member_id, kind, body, app, at) values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'problem',
   'The photo keeps spinning.', '{"version": 1}', now());
insert into public.feedback_issues (feedback_id, number, url, at) values
  ('f1000000-0000-0000-0000-000000000001', 7, 'https://github.com/o/r/issues/7', now());

select throws_ok($$update public.feedback set body = 'Changed'$$, '42501', null, 'a message can''t be changed');
select throws_ok($$delete from public.feedback$$, '42501', null, 'a message can''t be deleted');
select throws_ok($$update public.feedback_issues set number = 8$$, '42501', null, 'its issue can''t be changed');
select throws_ok($$delete from public.feedback_issues$$, '42501', null, 'its issue can''t be deleted');
select throws_ok(
  $$insert into public.feedback (id, member_id, kind, body, app, at) values
    (gen_random_uuid(), 'f0000000-0000-0000-0000-000000000001', 'idea', '', '{"version": 1}', now())$$,
  '23514', null, 'a message has words'
);
select throws_ok(
  $$insert into public.feedback (id, member_id, kind, body, screenshots, app, at) values
    (gen_random_uuid(), 'f0000000-0000-0000-0000-000000000001', 'idea', 'Four', '{a,b,c,d}', '{"version": 1}', now())$$,
  '23514', null, 'a message has at most 3 screenshots'
);

delete from auth.users where id = 'f0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.feedback where member_id = 'f0000000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.feedback_issues where feedback_id = 'f1000000-0000-0000-0000-000000000001'),
  0, 'deleting the account takes its messages and their issues with it'
);

select * from finish();
rollback;
