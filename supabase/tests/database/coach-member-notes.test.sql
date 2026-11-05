-- The coach's morning note to each member: one a member a squad a day, never changed, gone with
-- the member or the squad; delivered once.
begin;
select plan(9);

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

delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
select is((select count(*)::int from public.coach_member_notes), 1, 'a deleted account takes its notes');
delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.coach_member_notes), 0, 'an ended squad takes its notes');
select is((select count(*)::int from public.coach_member_note_deliveries), 0, 'and their deliveries');
select is((select count(*)::int from public.coach_member_note_reads), 0, 'and when they were put away');

select * from finish();
rollback;
