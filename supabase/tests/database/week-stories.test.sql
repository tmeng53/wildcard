-- A frozen 每周战报 is never changed: only a deleted account or squad takes its rows.
begin;
select plan(7);

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001', 'gus@example.com'),
  ('e0000000-0000-0000-0000-000000000002', 'hal@example.com');
insert into public.squads (id, name, created_by, invite_code) values
  ('5e000000-0000-0000-0000-000000000001', '早八跑团', 'e0000000-0000-0000-0000-000000000001', 'E7M2QX9P');
insert into public.squad_members (squad_id, member_id) values
  ('5e000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001'),
  ('5e000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002');
insert into public.week_stories (squad_id, week_start, story) values
  ('5e000000-0000-0000-0000-000000000001', '2026-10-19', '{"version":1,"name":"早八跑团","scene":"gym"}');
insert into public.week_story_members (squad_id, week_start, member_id, position, page) values
  ('5e000000-0000-0000-0000-000000000001', '2026-10-19', 'e0000000-0000-0000-0000-000000000001', 0, '{"version":1}'),
  ('5e000000-0000-0000-0000-000000000001', '2026-10-19', 'e0000000-0000-0000-0000-000000000002', 1, '{"version":1}');

select throws_ok(
  $$update public.week_stories set story = '{"version":1,"name":"改名","scene":"pool"}'$$,
  '42501', 'week_stories is frozen', 'the squad''s part can''t be changed'
);
select throws_ok(
  $$delete from public.week_stories$$, '42501', 'week_stories is frozen', 'or deleted'
);
select throws_ok(
  $$update public.week_story_members set position = 5$$,
  '42501', 'week_story_members is frozen', 'a member''s part can''t be changed'
);
select throws_ok(
  $$delete from public.week_story_members$$, '42501', 'week_story_members is frozen', 'or deleted'
);
select throws_ok(
  $$insert into public.week_stories (squad_id, week_start, story) values
    ('5e000000-0000-0000-0000-000000000001', '2026-10-20', '{"version":1}')$$,
  '23514', null, 'a week starts on a Monday'
);

delete from auth.users where id = 'e0000000-0000-0000-0000-000000000002';
select is(
  (select array_agg(member_id::text) from public.week_story_members),
  array['e0000000-0000-0000-0000-000000000001'],
  'a deleted account takes its part of the story with it'
);

delete from auth.users where id = 'e0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.week_stories), 0,
  'and the squad going with its last member takes the story'
);

select * from finish();
rollback;
