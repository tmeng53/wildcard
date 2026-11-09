-- What the team and events give: dedicated badges and vouchers in their catalogs, logged and never
-- deleted; `event` triggers; grants by event once an occurrence; and which feedback we adopted.
begin;
select plan(22);

insert into auth.users (id, email) values ('e3000000-0000-0000-0000-000000000001', 'tia@example.com');

select throws_ok(
  $$insert into public.rewards (kind, id) values ('badge', 'Bug Hunter')$$,
  '23514', null, 'a badge has a catalog id'
);
insert into public.rewards (kind, id) values ('badge', 'bug-hunter'), ('voucher', 'premium-week'),
  ('piece', 'thanks-bulb');
select throws_ok(
  $$insert into public.badges (id, names, glyph, tone)
    values ('bug-hunter', '{"zh-Hans": "捉虫队", "zh-Hant": "捉蟲隊", "en": "Bug Hunter"}', 'ladybug.fill', '#E65345')$$,
  '23514', null, 'a badge''s names carry their version'
);
insert into public.badges (id, names, glyph, tone) values ('bug-hunter',
  '{"version": 1, "zh-Hans": "捉虫队", "zh-Hant": "捉蟲隊", "en": "Bug Hunter"}', 'ladybug.fill', '#E65345');
update public.badges set tone = '#1F2128' where id = 'bug-hunter';
update public.badges set tone = '#1F2128' where id = 'bug-hunter';
select is(
  (select array_agg(op order by id) from public.reward_catalog_events where value ->> 'id' = 'bug-hunter'),
  array['INSERT', 'UPDATE'], 'a badge''s change is logged once, and a save that changed nothing is not'
);
select throws_ok($$delete from public.badges$$, '42501', null, 'a badge is never deleted');
select throws_ok(
  $$update public.badges set added_at = now() - interval '1 day'$$, '42501', null, 'a badge keeps its id'
);
select throws_ok(
  $$insert into public.vouchers (id, premium_days) values ('premium-week', 0)$$,
  '23514', null, 'a voucher is worth a day at least'
);
insert into public.vouchers (id, premium_days) values ('premium-week', 7);
select throws_ok($$delete from public.reward_catalog_events$$, '42501', null, 'the catalog log refuses a delete');

select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind) values ('badge', 'bug-hunter', 'event')$$,
  '23514', null, 'an event trigger names its events'
);
select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind, sports, after, counts_from)
    values ('badge', 'bug-hunter', 'training', '{}', 1, now())$$,
  '23514', null, 'training gives only what the wardrobe holds'
);
select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind, events) values ('badge', 'bug-hunter', 'event', '{Bug Adopted}')$$,
  '23514', null, 'an event has a kebab name'
);
insert into public.reward_triggers (reward_kind, reward_id, kind, events) values
  ('badge', 'bug-hunter', 'event', '{bug-adopted}'),
  ('voucher', 'premium-week', 'event', '{bug-adopted,idea-adopted}'),
  ('piece', 'thanks-bulb', 'event', '{idea-adopted}');
select ok(
  (select count(*) = 3 from public.reward_trigger_events where value ->> 'kind' = 'event'),
  'event triggers are logged with the rest'
);

-- A grant by an event: once an occurrence, and a piece once whatever gave it.
insert into public.grants (member_id, reward_kind, reward_id, via, event, event_id, at)
values ('e3000000-0000-0000-0000-000000000001', 'badge', 'bug-hunter', 'event', 'bug-adopted', 'f1', now());
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, event, event_id, at)
    values ('e3000000-0000-0000-0000-000000000001', 'badge', 'bug-hunter', 'event', 'bug-adopted', 'f1', now())$$,
  '23505', null, 'an occurrence gives a badge once'
);
insert into public.grants (member_id, reward_kind, reward_id, via, event, event_id, at)
values ('e3000000-0000-0000-0000-000000000001', 'badge', 'bug-hunter', 'event', 'bug-adopted', 'f2', now());
insert into public.grants (member_id, reward_kind, reward_id, via, admin_id, at) values
  ('e3000000-0000-0000-0000-000000000001', 'badge', 'bug-hunter', 'team', 'e3000000-0000-0000-0000-000000000009', now()),
  ('e3000000-0000-0000-0000-000000000001', 'badge', 'bug-hunter', 'team', 'e3000000-0000-0000-0000-000000000009', now());
select is(
  (select count(*)::int from public.grants where reward_id = 'bug-hunter'), 4,
  'a badge is held many times: once an occurrence, and each time the team gives it'
);
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, event, at)
    values ('e3000000-0000-0000-0000-000000000001', 'voucher', 'premium-week', 'event', 'bug-adopted', now())$$,
  '23514', null, 'an event''s grant names which time it happened'
);
insert into public.grants (member_id, reward_kind, reward_id, via, event, event_id, at)
values ('e3000000-0000-0000-0000-000000000001', 'piece', 'thanks-bulb', 'event', 'idea-adopted', 'f3', now());
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, event, event_id, at)
    values ('e3000000-0000-0000-0000-000000000001', 'piece', 'thanks-bulb', 'event', 'idea-adopted', 'f4', now())$$,
  '23505', null, 'a piece is held once, whichever time gave it'
);
select throws_ok($$update public.grants set event_id = 'f9'$$, '42501', null, 'an event''s grant is never changed');

-- Which feedback we adopted: once a message, never changed, gone only with the message.
insert into public.feedback (id, member_id, kind, body, app, at)
values ('e4000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'problem',
  '打卡按钮没反应', '{"version": 1}', now());
insert into public.feedback_adoptions (feedback_id, kind, admin_id)
values ('e4000000-0000-0000-0000-000000000001', 'bug', 'e3000000-0000-0000-0000-000000000009');
select throws_ok(
  $$insert into public.feedback_adoptions (feedback_id, kind, admin_id)
    values ('e4000000-0000-0000-0000-000000000001', 'idea', 'e3000000-0000-0000-0000-000000000009')$$,
  '23505', null, 'a message is adopted once'
);
select throws_ok(
  $$insert into public.feedback_adoptions (feedback_id, kind, admin_id)
    values ('e4000000-0000-0000-0000-000000000002', 'bug', 'e3000000-0000-0000-0000-000000000009')$$,
  '23503', null, 'only a message we were sent is adopted'
);
select throws_ok(
  $$update public.feedback_adoptions set kind = 'idea'$$, '42501', null, 'an adoption is never changed'
);
select throws_ok($$delete from public.feedback_adoptions$$, '42501', null, 'an adoption is never taken back');

delete from auth.users where id = 'e3000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.grants) + (select count(*)::int from public.feedback_adoptions), 0,
  'deleting the account takes its grants and its messages'' adoptions'
);
select ok(
  (select count(*) = 1 from public.badges) and (select count(*) = 1 from public.vouchers),
  'the catalogs stay'
);

select * from finish();
rollback;
