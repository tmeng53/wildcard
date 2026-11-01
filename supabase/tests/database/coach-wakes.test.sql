-- The coach at work: one coach a squad, hires logged; one wake per check-in and per squad-day; files, notes and usage that only
-- grow, until the squad ends or (for a member's page) the member's account goes.
begin;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'leo@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'coach-wakes-test');
insert into public.check_ins (id, member_id, day, created_at, kind, payload)
  values ('44444444-4444-4444-8444-444444444444', '11111111-1111-4111-8111-111111111111',
    '2026-11-01', now(), 'trained', '{"version": 1, "sport": "run"}');

insert into public.squad_coaches (squad_id, coach_id) values ('33333333-3333-4333-8333-333333333333', 'xiaohun');
select throws_ok($$insert into public.squad_coaches (squad_id, coach_id)
  values ('33333333-3333-4333-8333-333333333333', 'xiaohun')$$, '23505', null, 'a squad has one coach at a time');
insert into public.squad_coach_events (squad_id, kind, coach_id, changed_by)
  values ('33333333-3333-4333-8333-333333333333', 'hired', 'xiaohun', '11111111-1111-4111-8111-111111111111');
select throws_ok($$update public.squad_coach_events set kind = 'fired'$$, '42501', null, 'the hires'' log never changes');

insert into public.coach_wakes (id, squad_id, reason, check_in_id) overriding system value
  values (1, '33333333-3333-4333-8333-333333333333', 'checkIn', '44444444-4444-4444-8444-444444444444');
insert into public.coach_wakes (id, squad_id, reason, day) overriding system value
  values (2, '33333333-3333-4333-8333-333333333333', 'daily', '2026-11-01');
select throws_ok($$insert into public.coach_wakes (squad_id, reason, day)
  values ('33333333-3333-4333-8333-333333333333', 'daily', '2026-11-01')$$,
  '23505', null, 'one daily wake a squad a day');
select throws_ok($$insert into public.coach_wakes (squad_id, reason, day)
  values ('33333333-3333-4333-8333-333333333333', 'checkIn', '2026-11-01')$$,
  '23514', null, 'a check-in wake names its check-in');

insert into public.coach_files (squad_id, path, member_id, body, wake_id) values
  ('33333333-3333-4333-8333-333333333333', 'memory.md', null, '米亚爱跑步', 1),
  ('33333333-3333-4333-8333-333333333333', 'people/22222222-2222-4222-8222-222222222222.md',
    '22222222-2222-4222-8222-222222222222', '怕下雨', 2);
select throws_ok($$insert into public.coach_files (squad_id, path, member_id, body)
  values ('33333333-3333-4333-8333-333333333333', 'people/22222222-2222-4222-8222-222222222222.md',
    '11111111-1111-4111-8111-111111111111', 'x')$$,
  '23514', null, 'a member''s page is at their own path');
select throws_ok($$insert into public.coach_files (squad_id, path, body)
  values ('33333333-3333-4333-8333-333333333333', '../secrets.md', 'x')$$,
  '23514', null, 'files are only the squad''s own');
select throws_ok($$update public.coach_files set body = '改' where path = 'memory.md'$$,
  '42501', null, 'a file version is never changed');
insert into public.coach_notes (squad_id, coach_id, day, text, wake_id)
  values ('33333333-3333-4333-8333-333333333333', 'xiaohun', '2026-11-01', '先动起来', 2);
select throws_ok($$insert into public.coach_notes (squad_id, coach_id, day, text)
  values ('33333333-3333-4333-8333-333333333333', 'xiaohun', '2026-11-01', '再来一句')$$,
  '23505', null, 'one 战术板 line a squad a day');
insert into public.coach_usage (squad_id, wake_id, coach_id, model, requests, input_tokens, output_tokens, cost_micros)
  values ('33333333-3333-4333-8333-333333333333', 1, 'xiaohun', 'openai/gpt-6-luna', 2, 12000, 800, 4600);
select throws_ok($$delete from public.coach_usage$$, '42501', null, 'usage is never removed');

-- The check-in's deletion takes its wake; what the wake wrote stays.
delete from public.check_ins where id = '44444444-4444-4444-8444-444444444444';
select is((select wake_id from public.coach_files where path = 'memory.md'), null, 'a file outlives its wake');
select is((select count(*)::int from public.coach_usage), 1, 'usage outlives its wake');

-- A member's deletion takes their page, and the squad's end everything else.
-- A deleted account leaves the log's who; its page goes with it.
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select changed_by from public.squad_coach_events), null, 'a hire outlives who made it');
delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
select is((select array_agg(path) from public.coach_files), array['memory.md'], 'a member''s page goes with them');
delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is(
  (select count(*)::int from public.coach_files) + (select count(*)::int from public.coach_notes)
    + (select count(*)::int from public.coach_usage) + (select count(*)::int from public.coach_wakes)
    + (select count(*)::int from public.squad_coaches) + (select count(*)::int from public.squad_coach_events),
  0, 'the squad''s end takes its coaching'
);

select * from finish();
rollback;
