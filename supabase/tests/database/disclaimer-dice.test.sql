-- The 请假条 dice: one row of lines, never deleted, and a log that only grows, except that it
-- forgets which admin made a change once that admin deletes their account.
begin;
select plan(8);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000004', 'admin@example.com');
insert into public.disclaimer_dice_events (changed_by, dice) values
  ('d0000000-0000-0000-0000-000000000004', '{"version": 1}');

select is((select jsonb_array_length(lines) from public.disclaimer_dice), 8, 'the dice start with the app''s 8 lines');
select is(
  (select lines -> 0 from public.disclaimer_dice),
  '{"zhHans": "昨天的腿还没回来", "en": "My legs haven''t come back from yesterday", "zhHant": "昨天的腿還沒回來"}'::jsonb,
  'each line comes in every language'
);
select throws_ok($$delete from public.disclaimer_dice$$, '42501', null, 'the dice keep their row');
select throws_ok($$insert into public.disclaimer_dice (only_row, lines) values (false, '[{}]')$$, '23514', null, 'there is only one row of dice');
select throws_ok($$update public.disclaimer_dice set lines = '[]'$$, '23514', null, 'the dice always have a line');
select throws_ok($$update public.disclaimer_dice_events set dice = '{"version": 2}'$$, '42501', null, 'the log refuses an update');
select throws_ok($$truncate public.disclaimer_dice_events$$, '42501', null, 'the log refuses a truncate');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000004';
select is(
  (select count(*)::int from public.disclaimer_dice_events where changed_by is null and dice = '{"version": 1}'),
  1, 'the log keeps the deleted admin''s change, with no one named'
);

select * from finish();
rollback;
