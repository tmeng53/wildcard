-- Replies to the coach and its answers: a comment replies to a member or a coach, never both;
-- one answer a squad a reply, never changed, gone with the reply, its check-in or the squad.
begin;
select plan(11);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'leo@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'coach-answers-test');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('44444444-4444-4444-8444-444444444444', '11111111-1111-4111-8111-111111111111',
    '2026-11-03', now(), 'trained', '{"version": 1, "sport": "run"}');
insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to_coach, commented_at) values
  ('c1000000-0000-4000-8000-000000000001', '44444444-4444-4444-8444-444444444444',
    '22222222-2222-4222-8222-222222222222', '教练你也跑', 'xiaohun', now()),
  ('c1000000-0000-4000-8000-000000000002', '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111', '他不跑', 'xiaohun', now());

select throws_ok($$insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to, reply_to_coach, commented_at)
  values ('c1000000-0000-4000-8000-000000000009', '44444444-4444-4444-8444-444444444444',
    '22222222-2222-4222-8222-222222222222', '都回', '11111111-1111-4111-8111-111111111111', 'xiaohun', now())$$,
  '23514', null, 'a comment replies to a member or a coach, never both');
select throws_ok($$insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to_coach, commented_at)
  values ('c1000000-0000-4000-8000-000000000009', '44444444-4444-4444-8444-444444444444',
    '22222222-2222-4222-8222-222222222222', '你是谁', 'nobody', now())$$,
  '23503', null, 'only to a coach there is');
select throws_ok($$update public.check_in_comments set reply_to_coach = null
  where id = 'c1000000-0000-4000-8000-000000000001'$$, '42501', null, 'a reply to the coach is never changed');

insert into public.coach_wakes (id, squad_id, reason, check_in_id, comment_id) overriding system value values
  (1, '33333333-3333-4333-8333-333333333333', 'comment', '44444444-4444-4444-8444-444444444444',
    'c1000000-0000-4000-8000-000000000001');
select throws_ok($$insert into public.coach_wakes (squad_id, reason, check_in_id)
  values ('33333333-3333-4333-8333-333333333333', 'comment', '44444444-4444-4444-8444-444444444444')$$,
  '23514', null, 'a reply''s wake names the reply');
select throws_ok($$insert into public.coach_wakes (squad_id, reason, check_in_id, comment_id)
  values ('33333333-3333-4333-8333-333333333333', 'comment', '44444444-4444-4444-8444-444444444444',
    'c1000000-0000-4000-8000-000000000001')$$,
  '23505', null, 'one wake a squad a reply');

insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text, wake_id) values
  ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444',
    'c1000000-0000-4000-8000-000000000001', 'xiaohun', '我负责喊', 1),
  ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444',
    'c1000000-0000-4000-8000-000000000002', 'xiaohun', '喊也是练', null);
select throws_ok($$insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text)
  values ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444',
    'c1000000-0000-4000-8000-000000000001', 'xiaohun', '再说一句')$$,
  '23505', null, 'one answer a squad a reply');
select throws_ok($$update public.coach_answers set text = '改'$$, '42501', null, 'an answer is never changed');
select throws_ok($$delete from public.coach_answers$$, '42501', null, 'an answer is never removed');

-- Deleting the reply takes its answer, and its wake (the answer keeps no wake then).
delete from public.check_in_comments where id = 'c1000000-0000-4000-8000-000000000001';
select is((select array_agg(text) from public.coach_answers), array['喊也是练'], 'an answer goes with its reply');
select is((select count(*)::int from public.coach_wakes), 0, 'and the reply''s wake with it');

delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.coach_answers), 0, 'the squad''s end takes its answers');

select * from finish();
rollback;
