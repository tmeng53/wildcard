-- The coach's replies to check-ins: one a squad a check-in, a line, an emoji or both, never
-- changed, gone with the check-in, its author's account or the squad.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'coach-replies-test');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('44444444-4444-4444-8444-444444444444', '11111111-1111-4111-8111-111111111111',
    '2026-11-02', now(), 'trained', '{"version": 1, "sport": "run"}'),
  ('55555555-5555-4555-8555-555555555555', '11111111-1111-4111-8111-111111111111',
    '2026-11-03', now(), 'trained', '{"version": 1, "sport": "run"}');
insert into public.coach_wakes (id, squad_id, reason, check_in_id) overriding system value values
  (1, '33333333-3333-4333-8333-333333333333', 'checkIn', '44444444-4444-4444-8444-444444444444'),
  (2, '33333333-3333-4333-8333-333333333333', 'checkIn', '55555555-5555-4555-8555-555555555555');

insert into public.coach_replies (squad_id, check_in_id, coach_id, text, emoji, wake_id) values
  ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444', 'xiaohun', '腿还在吗', '💪', 1),
  ('33333333-3333-4333-8333-333333333333', '55555555-5555-4555-8555-555555555555', 'xiaohun', null, '🔥', 2);
select throws_ok($$insert into public.coach_replies (squad_id, check_in_id, coach_id, text)
  values ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444', 'xiaohun', '再说一句')$$,
  '23505', null, 'one reply a squad a check-in');
select throws_ok($$insert into public.coach_replies (squad_id, check_in_id, coach_id)
  values ('33333333-3333-4333-8333-333333333333', '55555555-5555-4555-8555-555555555555', 'xiaohun')$$,
  '23514', null, 'a reply says or reacts something');
select throws_ok($$insert into public.coach_replies (squad_id, check_in_id, coach_id, text)
  values ('33333333-3333-4333-8333-333333333333', '55555555-5555-4555-8555-555555555555', 'xiaohun', repeat('跑', 201))$$,
  '23514', null, 'a reply holds at most 200 characters, its longest in any language');
select throws_ok($$update public.coach_replies set text = '改'$$, '42501', null, 'a reply is never changed');
select throws_ok($$delete from public.coach_replies$$, '42501', null, 'a reply is never removed');
-- Refused like the other coach logs' truncates (settings_log_append_only, which raises before or while reading the row).
select throws_ok($$truncate public.coach_replies$$, null, null, 'nor all of them');

-- The check-in's deletion takes its reply (and its wake).
delete from public.check_ins where id = '44444444-4444-4444-8444-444444444444';
select is((select array_agg(emoji) from public.coach_replies), array['🔥'], 'a reply goes with its check-in');

-- The author's account takes their check-ins, and the replies to them.
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.coach_replies), 0, 'replies go with the author''s account');

insert into auth.users (id, email) values ('11111111-1111-4111-8111-111111111111', 'mia@example.com');
insert into public.check_ins (id, member_id, day, created_at, kind, payload) values
  ('66666666-6666-4666-8666-666666666666', '11111111-1111-4111-8111-111111111111',
    '2026-11-03', now(), 'trained', '{"version": 1, "sport": "run"}');
insert into public.check_in_squads (check_in_id, squad_id, position)
  values ('66666666-6666-4666-8666-666666666666', '33333333-3333-4333-8333-333333333333', 1);
insert into public.coach_replies (squad_id, check_in_id, coach_id, text)
  values ('33333333-3333-4333-8333-333333333333', '66666666-6666-4666-8666-666666666666', 'xiaohun', '收到');
delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.coach_replies), 0, 'the squad''s end takes its replies');

select * from finish();
rollback;
