-- The coach's morning note to each member: one a member a squad a day, never changed, gone with
-- the member or the squad; delivered once.
begin;
select plan(30);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'leo@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'coach-member-notes-test');
insert into public.coach_member_notes (id, squad_id, member_id, coach_id, day, text) overriding system value values
  (1, '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-05', '今天练力量'),
  (2, '33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'xiaohun', '2026-11-05', '今天歇着');

select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-05', '再来一张')$$,
  '23505', null, 'one note a member a squad a day');
select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-06', '')$$,
  '23514', null, 'a note has words');
select throws_ok($$update public.coach_member_notes set text = '改了' where id = 1$$,
  '42501', null, 'a note is never changed');

insert into public.coach_member_note_deliveries (note_id) values (1);
select throws_ok($$insert into public.coach_member_note_deliveries (note_id) values (1)$$,
  '23505', null, 'delivered once');
insert into public.coach_member_note_reads (note_id) values (1);
select throws_ok($$insert into public.coach_member_note_reads (note_id) values (1)$$,
  '23505', null, 'put away once');
select throws_ok($$delete from public.coach_member_note_reads where note_id = 1$$,
  '42501', null, 'a put-away stays');
select throws_ok($$update public.coach_member_note_deliveries set at = now() where note_id = 1$$,
  '42501', null, 'a delivery stays');

-- A day's challenge: a title, and an amount only with its unit; answered once.
select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-06', '喝水', '喝水', 8)$$,
  '23514', null, 'an amount comes with its unit');
select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_title)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-06', '喝水', '一二三四五六七八九')$$,
  '23514', null, 'a challenge title is short');
insert into public.coach_member_notes (id, squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount, challenge_unit)
  overriding system value values
  (3, '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-06', '今天多喝水', '喝水', 8, '杯');
insert into public.coach_challenge_answers (note_id, answer) values (3, 'accepted');
select throws_ok($$insert into public.coach_challenge_answers (note_id, answer) values (3, 'declined')$$,
  '23505', null, 'a challenge is answered once');
select throws_ok($$update public.coach_challenge_answers set answer = 'declined' where note_id = 3$$,
  '42501', null, 'an answer stands');
select throws_ok($$insert into public.coach_challenge_answers (note_id, answer) values (1, 'maybe')$$,
  '23514', null, 'an answer is accepted or declined');
insert into public.coach_challenge_completions (note_id, by) values (3, 'coach');
select throws_ok($$insert into public.coach_challenge_completions (note_id, by) values (3, 'member')$$,
  '23505', null, 'a challenge is done once');
select throws_ok($$update public.coach_challenge_completions set by = 'member' where note_id = 3$$,
  '42501', null, 'who marked it done stands');
select throws_ok($$insert into public.coach_challenge_completions (note_id, by) values (1, 'squad')$$,
  '23514', null, 'the member or the coach marks it done');
select throws_ok($$insert into public.coach_challenge_answers (note_id, answer, reason) values (1, 'accepted', '鸡蛋过敏')$$,
  '23514', null, 'a reason only comes with letting it go');
insert into public.coach_member_notes (id, squad_id, member_id, coach_id, day, text, challenge_title)
  overriding system value values
  (4, '33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'xiaohun', '2026-11-06', '早餐加个蛋', '吃鸡蛋');
insert into public.coach_challenge_answers (note_id, answer, reason) values (4, 'declined', '我鸡蛋过敏');
select is((select reason from public.coach_challenge_answers where note_id = 4), '我鸡蛋过敏', 'why they let it go is kept');

-- The line under a challenge's title is short, and only with a challenge.
select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_line)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-07', '歇着', '多睡会儿')$$,
  '23514', null, 'a challenge line needs its challenge');
select throws_ok($$insert into public.coach_member_notes (squad_id, member_id, coach_id, day, text, challenge_title, challenge_line)
  values ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'xiaohun', '2026-11-07', '歇着', '早睡', repeat('睡', 25))$$,
  '23514', null, 'a challenge line is short');

-- The coach page's cards each member saw: once, never changed, gone with the member or squad.
insert into public.coach_card_seen (member_id, squad_id, kind, card_id) values
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'note', '1'),
  ('22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333', 'gift', 'towel-fleece');
select throws_ok($$insert into public.coach_card_seen (member_id, squad_id, kind, card_id)
  values ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'note', '1')$$,
  '23505', null, 'a card is seen once');
select throws_ok($$insert into public.coach_card_seen (member_id, squad_id, kind, card_id)
  values ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'poster', '1')$$,
  '23514', null, 'a card is one of the kinds');
insert into public.coach_card_seen (member_id, squad_id, kind, card_id) values
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'challengeDone', '3');
select throws_ok($$delete from public.coach_card_seen where card_id = '1'$$,
  '42501', null, 'a seen card stays seen');

delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
select is((select count(*)::int from public.coach_card_seen), 2, 'a deleted account takes what it saw');
select is((select count(*)::int from public.coach_member_notes), 2, 'a deleted account takes its notes');
delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.coach_member_notes), 0, 'an ended squad takes its notes');
select is((select count(*)::int from public.coach_member_note_deliveries), 0, 'and their deliveries');
select is((select count(*)::int from public.coach_member_note_reads), 0, 'and when they were put away');
select is((select count(*)::int from public.coach_challenge_completions), 0, 'and their challenges done');
select is((select count(*)::int from public.coach_challenge_answers), 0, 'and the answers to their challenges');
select is((select count(*)::int from public.coach_card_seen), 0, 'and the cards its members saw');

select * from finish();
rollback;
