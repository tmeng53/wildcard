-- A comment is never changed once written; an account's deletion clears the replies to it and
-- takes its own comments with it.
begin;
select plan(5);

insert into auth.users (id, email) values
  ('c1000000-0000-0000-0000-000000000001', 'author@example.com'),
  ('c1000000-0000-0000-0000-000000000002', 'mate@example.com'),
  ('c1000000-0000-0000-0000-000000000003', 'leaver@example.com');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', current_date, now(),
   'disclaimer', '{"version":1,"text":"下雨了"}');
insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to, commented_at) values
  ('c1200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
   'c1000000-0000-0000-0000-000000000002', '它会习惯的', 'c1000000-0000-0000-0000-000000000003', now()),
  ('c1200000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001',
   'c1000000-0000-0000-0000-000000000003', '下次带我', null, now());

select throws_ok(
  $$update public.check_in_comments set text = '改了' where id = 'c1200000-0000-0000-0000-000000000001'$$,
  '42501', null, 'a comment''s words can''t be changed'
);
select throws_ok(
  $$update public.check_in_comments set reply_to = null where id = 'c1200000-0000-0000-0000-000000000001'$$,
  '42501', null, 'a reply can''t be cleared while the account it replies to exists'
);

select lives_ok(
  $$delete from auth.users where id = 'c1000000-0000-0000-0000-000000000003'$$,
  'deleting the replied-to account works'
);
select results_eq(
  $$select text, reply_to from public.check_in_comments where id = 'c1200000-0000-0000-0000-000000000001'$$,
  $$values ('它会习惯的'::text, null::uuid)$$,
  'the reply stays, as a plain comment'
);
select is(
  (select count(*)::int from public.check_in_comments where member_id = 'c1000000-0000-0000-0000-000000000003'),
  0, 'the deleted account''s own comments go with it'
);

select * from finish();
rollback;
