-- What the database keeps true about weekly awards however the API writes them.
begin;
select plan(4);

insert into public.squads (id, name, invite_code)
values ('c0000000-0000-0000-0000-000000000001', 'squad', 'AWARDS01');

select lives_ok(
  $$insert into public.weekly_awards (squad_id, week_start, awards)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19', '{"version":1}')$$,
  'a squad''s awards for a week starting on Monday are saved'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start, awards)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-19', '{"version":1}')$$,
  '23505', 'duplicate key value violates unique constraint "weekly_awards_pkey"',
  'a squad has one set of awards a week'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start, awards)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-20', '{"version":1}')$$,
  '23514', null,
  'a week starts on a Monday'
);
select throws_ok(
  $$insert into public.weekly_awards (squad_id, week_start, awards)
    values ('c0000000-0000-0000-0000-000000000001', '2026-10-26', '{}')$$,
  '23514', null,
  'stored awards carry their version'
);

select * from finish();
rollback;
