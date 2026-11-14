-- Coach messages (教练消息卡): each save a new row, never changed; who got one and what they
-- answered are their own logs, never changed, gone with the member's account.
begin;
select plan(13);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'leo@example.com');

insert into public.coach_messages (message_id, changed_by, message) values
  ('enjoying', '22222222-2222-4222-8222-222222222222', '{"version": 1}');
select throws_ok($$insert into public.coach_messages (message_id, message) values ('Enjoying!', '{"version": 1}')$$,
  '23514', null, 'a message''s id is a slug');
select throws_ok($$insert into public.coach_messages (message_id, message) values ('enjoying', '{}')$$,
  '23514', null, 'a message carries its version');
select throws_ok($$update public.coach_messages set message = '{"version": 2}'$$, '42501', null,
  'a message is never changed in place');
select throws_ok($$delete from public.coach_messages$$, '42501', null, 'nor removed');

insert into public.coach_message_deliveries (member_id, message_id, squad_id, coach_id) values
  ('11111111-1111-4111-8111-111111111111', 'enjoying', '33333333-3333-4333-8333-333333333333', 'maotou');
select throws_ok($$insert into public.coach_message_deliveries (member_id, message_id, squad_id, coach_id)
  values ('11111111-1111-4111-8111-111111111111', 'enjoying', '33333333-3333-4333-8333-333333333333', 'maotou')$$,
  '23505', null, 'a member gets a message once');
select throws_ok($$update public.coach_message_deliveries set coach_id = 'yalina'$$, '42501', null,
  'who said it never changes');

insert into public.coach_message_answers (member_id, message_id, path, part, button) values
  ('11111111-1111-4111-8111-111111111111', 'enjoying', '', 'tap', 'no');
insert into public.coach_message_answers (member_id, message_id, path, part, text) values
  ('11111111-1111-4111-8111-111111111111', 'enjoying', 'no', 'text', '打卡有点慢');
select throws_ok($$insert into public.coach_message_answers (member_id, message_id, path, part, button)
  values ('11111111-1111-4111-8111-111111111111', 'enjoying', '', 'tap', 'yes')$$,
  '23505', null, 'each part of a card is answered once');
select throws_ok($$insert into public.coach_message_answers (member_id, message_id, path, part, stars)
  values ('11111111-1111-4111-8111-111111111111', 'enjoying', '', 'stars', 6)$$,
  '23514', null, 'one to five stars');
select throws_ok($$insert into public.coach_message_answers (member_id, message_id, path, part, text)
  values ('11111111-1111-4111-8111-111111111111', 'enjoying', '', 'tap', '喜欢')$$,
  '23514', null, 'a tap names a button, nothing else');
select throws_ok($$delete from public.coach_message_answers$$, '42501', null,
  'an answer is never removed');

delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.coach_message_deliveries), 0,
  'the account takes what it got');
select is((select count(*)::int from public.coach_message_answers), 0, 'and what it answered');
select is((select count(*)::int from public.coach_messages), 1, 'the message stays');

select * from finish();
rollback;
