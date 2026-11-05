-- The squad's chat: a message is never changed, deleting the one it replies to leaves it a plain
-- message, the coach answers a message once, and the alerts and reads are append-only until the
-- account goes.
begin;
select plan(7);

insert into auth.users (id, email) values
  ('e1000000-0000-0000-0000-000000000001', 'writer@example.com'),
  ('e1000000-0000-0000-0000-000000000002', 'mate@example.com');
insert into public.squads (id, name, created_by, invite_code) values
  ('e1500000-0000-0000-0000-000000000001', '早八跑团', 'e1000000-0000-0000-0000-000000000001', 'E7M2QX9P');
insert into public.squad_messages (id, squad_id, member_id, kind, text, mentions_coach) values
  ('e1200000-0000-0000-0000-000000000001', 'e1500000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 'text', '@毛头 今天练啥', true);
insert into public.squad_messages (id, squad_id, member_id, kind, text, reply_to) values
  ('e1200000-0000-0000-0000-000000000002', 'e1500000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000002', 'text', '我也想知道', 'e1200000-0000-0000-0000-000000000001');
insert into public.squad_messages (squad_id, coach_id, kind, text, reply_to) values
  ('e1500000-0000-0000-0000-000000000001', 'xiaohun', 'text', '练腿', 'e1200000-0000-0000-0000-000000000001');
insert into public.squad_chat_alerts (squad_id, member_id, alerts) values
  ('e1500000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'all');

select throws_ok(
  $$update public.squad_messages set text = '改了' where id = 'e1200000-0000-0000-0000-000000000002'$$,
  '42501', null, 'a message''s words can''t be changed'
);
select throws_ok(
  $$insert into public.squad_messages (squad_id, coach_id, kind, text, reply_to) values
    ('e1500000-0000-0000-0000-000000000001', 'xiaohun', 'text', '再说一遍', 'e1200000-0000-0000-0000-000000000001')$$,
  '23505', null, 'the coach answers a message once'
);
select throws_ok(
  $$update public.squad_chat_alerts set alerts = 'none'$$,
  '42501', null, 'the alerts are append-only'
);

select lives_ok(
  $$delete from public.squad_messages where id = 'e1200000-0000-0000-0000-000000000001'$$,
  'its writer''s message can be deleted'
);
select is(
  (select reply_to from public.squad_messages where id = 'e1200000-0000-0000-0000-000000000002'),
  null, 'a reply to it stays, as a plain message'
);

select lives_ok(
  $$delete from auth.users where id = 'e1000000-0000-0000-0000-000000000002'$$,
  'deleting an account works'
);
select is(
  (select count(*)::int from public.squad_chat_alerts),
  0, 'the account''s alerts go with it'
);

select * from finish();
rollback;
