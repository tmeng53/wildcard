-- The AI coach: one row of settings, never deleted; coaches never deleted and keeping their
-- ids; and logs that only grow.
begin;
select plan(9);

select is((select count(*)::int from public.coach_settings), 1, 'the coach starts with its settings');
select is((select coaching from public.coach_settings), false, 'coaching starts off');
select throws_ok($$delete from public.coach_settings$$, '42501', null, 'the coach settings keep their row');
select throws_ok($$update public.coach_settings set model = 'anthropic/claude-haiku-5-5'$$, '23514', null, 'the coach runs on an OpenAI model');
select throws_ok($$delete from public.coaches where id = 'xiaohun'$$, '42501', null, 'a coach is never deleted');
select throws_ok($$update public.coaches set id = 'xiaohun2' where id = 'xiaohun'$$, '42501', null, 'a coach keeps its id');
select throws_ok($$update public.coach_catalog_events set coach = '{"version": 2}'$$, '42501', null, 'the coaches'' log refuses an update');
select throws_ok($$truncate public.coach_setting_events$$, '42501', null, 'the settings log refuses a truncate');
select is(
  (select count(*)::int from public.coach_catalog_events where coach_id = 'xiaohun' and changed_by is null),
  1, 'the log starts with the first coach'
);

select * from finish();
rollback;
