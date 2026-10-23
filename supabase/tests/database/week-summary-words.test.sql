-- The Sunday summary's words: one row, never deleted, and a log that only grows, except that it
-- forgets which admin made a change once that admin deletes their account.
begin;
select plan(7);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000002', 'admin@example.com');
insert into public.week_summary_word_events (changed_by, words) values
  ('d0000000-0000-0000-0000-000000000002', '{"version": 1}');

select is(
  (select words #>> '{awards,crown,title,zh-Hans}' from public.week_summary_words),
  '皇冠', 'the summary starts with its words'
);
select throws_ok($$delete from public.week_summary_words$$, '42501', null, 'the words keep their row');
select throws_ok($$insert into public.week_summary_words (only_row, words) values (false, '{"version": 1}')$$, '23514', null, 'there is only one row of words');
select throws_ok($$update public.week_summary_words set words = '{}'$$, '23514', null, 'the words carry a version');
select throws_ok($$delete from public.week_summary_word_events$$, '42501', null, 'the log refuses a delete');
select throws_ok($$truncate public.week_summary_word_events$$, '42501', null, 'the log refuses a truncate');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.week_summary_word_events where changed_by is null),
  2, 'the log keeps the first words and the deleted admin''s change, with no one named'
);

select * from finish();
rollback;
