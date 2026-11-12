-- A coach's letter to the next one: one try and at most one letter a change of coach, never
-- changed, gone with the squad.
begin;
select plan(8);

insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'coach-letters-test');
-- A second coach like the first, to change to.
insert into public.coaches
  select (jsonb_populate_record(c, jsonb_build_object('id', 'letter-test'))).*
  from public.coaches c where id = 'xiaohun';
insert into public.squad_coach_events (id, squad_id, kind, coach_id) overriding system value values
  (901, '33333333-3333-4333-8333-333333333333', 'fired', 'xiaohun'),
  (902, '33333333-3333-4333-8333-333333333333', 'hired', 'letter-test');
insert into public.coach_letter_tries (hire_event_id, squad_id)
  values (902, '33333333-3333-4333-8333-333333333333');

select throws_ok($$insert into public.coach_letter_tries (hire_event_id, squad_id)
  values (902, '33333333-3333-4333-8333-333333333333')$$,
  '23505', null, 'one try a change of coach');
select throws_ok($$insert into public.coach_letters (squad_id, hire_event_id, from_coach, to_coach, day, text)
  values ('33333333-3333-4333-8333-333333333333', 901, 'xiaohun', 'letter-test', '2026-11-08', '交给你了')$$,
  '23503', null, 'a letter only for a change it tried');
select throws_ok($$insert into public.coach_letters (squad_id, hire_event_id, from_coach, to_coach, day, text)
  values ('33333333-3333-4333-8333-333333333333', 902, 'xiaohun', 'letter-test', '2026-11-08', repeat('字', 401))$$,
  '23514', null, 'at most 400 characters (200 counted, English as half)');
select throws_ok($$insert into public.coach_letters (squad_id, hire_event_id, from_coach, to_coach, day, text)
  values ('33333333-3333-4333-8333-333333333333', 902, 'xiaohun', 'xiaohun', '2026-11-08', '交给你了')$$,
  '23514', null, 'never to itself');
insert into public.coach_letters (squad_id, hire_event_id, from_coach, to_coach, day, text)
  values ('33333333-3333-4333-8333-333333333333', 902, 'xiaohun', 'letter-test', '2026-11-08', '交给你了');
select throws_ok($$insert into public.coach_letters (squad_id, hire_event_id, from_coach, to_coach, day, text)
  values ('33333333-3333-4333-8333-333333333333', 902, 'xiaohun', 'letter-test', '2026-11-08', '再写一封')$$,
  '23505', null, 'one letter a change of coach');
select throws_ok($$update public.coach_letters set text = '改了'$$,
  '42501', null, 'a letter is never changed');

delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.coach_letters), 0, 'an ended squad takes its letters');
select is((select count(*)::int from public.coach_letter_tries), 0, 'and its tries');

select * from finish();
rollback;
