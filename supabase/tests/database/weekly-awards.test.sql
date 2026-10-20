-- What the database keeps true about weekly awards however the API writes them.
begin;
select plan(7);

insert into public.squads (id, name, invite_code)
values ('c0000000-0000-0000-0000-000000000001', 'squad', 'AWARDS01');
insert into auth.users (id, email)
values ('a0000000-0000-0000-0000-0000000000a1', 'awards@example.com');

select lives_ok(
  $$insert into public.weekly_awards (squad_id, week_start, failed_attempts, last_error)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19', 1, 'timeout')$$,
  'a squad''s week is kept with its failed tries before its awards are given'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19')$$,
  '23505', 'duplicate key value violates unique constraint "weekly_awards_pkey"',
  'a squad has one row of awards a week'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-20')$$,
  '23514', null,
  'a week starts on a Monday'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start, failed_attempts)
    values ('c0000000-0000-0000-0000-000000000001', '2026-11-09', -1)$$,
  '23514', null,
  'failed tries never go below none'
);
select throws_ok(
  $$insert into public.weekly_award_winners (squad_id, week_start, member_id, position, award)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19',
      'a0000000-0000-0000-0000-0000000000a1', 0, '{}')$$,
  '23514', null,
  'stored awards carry their version'
);
insert into public.weekly_award_winners (squad_id, week_start, member_id, position, award)
values ('c0000000-0000-0000-0000-000000000001', '2026-10-19',
  'a0000000-0000-0000-0000-0000000000a1', 0, '{"version":1}');
select throws_ok(
  $$insert into public.weekly_award_winners (squad_id, week_start, member_id, position, award)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19',
      'a0000000-0000-0000-0000-0000000000a2', 1, '{"version":1}')$$,
  '23503', null,
  'only a member with an account wins'
);
delete from auth.users where id = 'a0000000-0000-0000-0000-0000000000a1';
select is(
  (select count(*)::int from public.weekly_award_winners),
  0,
  'a deleted account takes its awards with it'
);

select * from finish();
rollback;
