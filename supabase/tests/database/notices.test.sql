-- The notices a member was told (the bell's history) and how far they read them: never
-- changed, gone with the member's account, and a squad's notices with the squad.
begin;
select plan(15);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'leo@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'notices-test');

insert into public.notices (member_id, squad_id, kind, subject) values
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'sceneMoved',
    '{"version": 1, "scene": "track", "by": "22222222-2222-4222-8222-222222222222"}'),
  ('11111111-1111-4111-8111-111111111111', null, 'unlocked',
    '{"version": 1, "kind": "store", "item": "deuce"}'),
  ('22222222-2222-4222-8222-222222222222', null, 'unlocked',
    '{"version": 1, "kind": "prop", "item": "racket"}');
select throws_ok($$insert into public.notices (member_id, kind, subject)
  values ('11111111-1111-4111-8111-111111111111', 'unlocked', '{"kind": "prop"}')$$,
  '23514', null, 'a notice''s subject carries its version');
select throws_ok($$update public.notices set kind = 'x'$$, '42501', null, 'a notice is never changed');
select throws_ok($$delete from public.notices$$, '42501', null, 'a notice is never removed');
select throws_ok($$truncate public.notices$$, null, null, 'nor all of them');

insert into public.notice_reads (member_id, seen_through) values
  ('11111111-1111-4111-8111-111111111111', 1);
select throws_ok($$update public.notice_reads set seen_through = 9$$, '42501', null, 'a read is never changed');
select throws_ok($$delete from public.notice_reads$$, '42501', null, 'a read is never removed');

delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select array_agg(kind order by id) from public.notices
  where member_id = '11111111-1111-4111-8111-111111111111'), array['unlocked'],
  'the squad''s end takes the notices about it');

delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.notices
  where member_id = '11111111-1111-4111-8111-111111111111'), 0, 'the account takes its notices');
select is((select count(*)::int from public.notice_reads), 0, 'and how far it read them');
select is((select count(*)::int from public.notices), 1, 'others'' notices stay');

-- Broadcasts: each save a new row, never changed; a member is told each once.
insert into public.broadcasts (broadcast_id, changed_by, broadcast) values
  ('soon', '22222222-2222-4222-8222-222222222222', '{"version": 1}');
select throws_ok($$insert into public.broadcasts (broadcast_id, broadcast) values ('Soon!', '{"version": 1}')$$,
  '23514', null, 'a broadcast''s id is a slug');
select throws_ok($$insert into public.broadcasts (broadcast_id, broadcast) values ('soon', '{}')$$,
  '23514', null, 'a broadcast carries its version');
select throws_ok($$update public.broadcasts set broadcast = '{"version": 2}'$$, '42501', null,
  'a broadcast is never changed in place');
insert into public.notices (member_id, kind, subject) values
  ('22222222-2222-4222-8222-222222222222', 'broadcast', '{"version": 1, "broadcast": "soon"}');
select throws_ok($$insert into public.notices (member_id, kind, subject) values
  ('22222222-2222-4222-8222-222222222222', 'broadcast', '{"version": 1, "broadcast": "soon"}')$$,
  '23505', null, 'a member is told a broadcast once');
delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
select is((select changed_by from public.broadcasts where broadcast_id = 'soon'), null,
  'a broadcast outlives the admin who wrote it');

select * from finish();
rollback;
