-- Which notices a member opened somewhere else: one row a notice, never changed, gone with the
-- account and with the notice (its squad's cascade).
begin;
select plan(6);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'mia@example.com');
insert into public.squads (id, name, invite_code)
  values ('33333333-3333-4333-8333-333333333333', 'squad', 'opens-test');
insert into public.notices (id, member_id, squad_id, kind, subject) overriding system value values
  (901, '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'sceneMoved',
    '{"version": 1, "scene": "track", "by": null}'),
  (902, '11111111-1111-4111-8111-111111111111', null, 'unlocked',
    '{"version": 1, "kind": "store", "item": "deuce"}');

insert into public.notice_opens (member_id, notice_id) values
  ('11111111-1111-4111-8111-111111111111', 901),
  ('11111111-1111-4111-8111-111111111111', 902);
select throws_ok($$insert into public.notice_opens (member_id, notice_id)
  values ('11111111-1111-4111-8111-111111111111', 901)$$, '23505', null, 'a notice is opened once');
select throws_ok($$update public.notice_opens set at = now()$$, '42501', null, 'an open is never changed');
select throws_ok($$delete from public.notice_opens$$, '42501', null, 'an open is never removed');
select throws_ok($$truncate public.notice_opens$$, null, null, 'nor all of them');

delete from public.squads where id = '33333333-3333-4333-8333-333333333333';
select is((select array_agg(notice_id order by notice_id) from public.notice_opens), array[902::bigint],
  'the squad''s end takes the opens of its notices');

delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.notice_opens), 0, 'the account takes its opens');

select * from finish();
rollback;
