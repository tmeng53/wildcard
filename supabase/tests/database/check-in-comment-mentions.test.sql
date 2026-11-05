-- Whom a comment @s is never changed; deleting the comment or a mentioned account removes the
-- row, and a comment's coach @ can't be changed either.
begin;
select plan(6);

insert into auth.users (id, email) values
  ('c5000000-0000-0000-0000-000000000001', 'author@example.com'),
  ('c5000000-0000-0000-0000-000000000002', 'mate@example.com'),
  ('c5000000-0000-0000-0000-000000000003', 'leaver@example.com');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('c5100000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', current_date, now(),
   'disclaimer', '{"version":1,"text":"下雨了"}');
insert into public.check_in_comments (id, check_in_id, member_id, text, commented_at, mentions_coach) values
  ('c5200000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', '@mate @leaver 明天一起', now(), null),
  ('c5200000-0000-0000-0000-000000000002', 'c5100000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000002', '@毛头 下雨还练吗', now(), 'xiaohun');
insert into public.check_in_comment_mentions (comment_id, member_id, position) values
  ('c5200000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002', 0),
  ('c5200000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000003', 1);

select throws_ok(
  $$update public.check_in_comment_mentions set position = 5
    where comment_id = 'c5200000-0000-0000-0000-000000000001' and position = 0$$,
  '42501', null, 'whom a comment @s can''t be changed'
);
select throws_ok(
  $$update public.check_in_comments set mentions_coach = null where id = 'c5200000-0000-0000-0000-000000000002'$$,
  '42501', null, 'a comment''s coach @ can''t be changed'
);
select throws_ok(
  $$insert into public.check_in_comment_mentions (comment_id, member_id, position) values
    ('c5200000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', 8)$$,
  '23514', null, 'a comment @s at most 8 people'
);

select lives_ok(
  $$delete from auth.users where id = 'c5000000-0000-0000-0000-000000000003'$$,
  'deleting a mentioned account works'
);
select results_eq(
  $$select member_id from public.check_in_comment_mentions
    where comment_id = 'c5200000-0000-0000-0000-000000000001'$$,
  $$values ('c5000000-0000-0000-0000-000000000002'::uuid)$$,
  'the deleted account''s @ goes, the others stay'
);
delete from public.check_in_comments where id = 'c5200000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.check_in_comment_mentions
    where comment_id = 'c5200000-0000-0000-0000-000000000001'),
  0, 'deleting the comment takes its @s with it'
);

select * from finish();
rollback;
