-- What the AI writes with: one row per module, never deleted, and logs that only grow, except
-- that they forget which admin made a change once that admin deletes their account.
begin;
select plan(14);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000001', 'admin@example.com');
insert into public.disclaimer_draft_setting_events (changed_by, settings) values
  ('d0000000-0000-0000-0000-000000000001', '{"version": 1}');
insert into public.weekly_award_setting_events (changed_by, settings) values
  ('d0000000-0000-0000-0000-000000000001', '{"version": 1}');

select is((select count(*)::int from public.disclaimer_draft_settings), 1, 'drafts start with their settings');
select is((select count(*)::int from public.weekly_award_settings), 1, 'the awards start with their settings');
select throws_ok($$delete from public.disclaimer_draft_settings$$, '42501', null, 'the draft settings keep their row');
select throws_ok($$truncate public.weekly_award_settings$$, '42501', null, 'the award settings keep their row');
select throws_ok($$insert into public.disclaimer_draft_settings (only_row, writing, model, instructions, batches_per_day, meme_chance) values (false, true, 'openai/x', 'x', 1, 0)$$, '23514', null, 'there is only one row of draft settings');
select throws_ok($$update public.disclaimer_draft_settings set model = 'gemini/flash'$$, '23514', null, 'a model names a provider the API knows');
select throws_ok($$update public.disclaimer_draft_settings set meme_chance = 1.5$$, '23514', null, 'a chance is from 0 to 1');
select throws_ok($$update public.weekly_award_settings set moves = '[]'$$, '23514', null, 'the moves are an object');
select throws_ok($$update public.disclaimer_draft_setting_events set settings = '{"version": 2}'$$, '42501', null, 'the draft settings log refuses an update');
select throws_ok($$delete from public.disclaimer_draft_setting_events$$, '42501', null, 'the draft settings log refuses a delete');
select throws_ok($$truncate public.weekly_award_setting_events$$, '42501', null, 'the award settings log refuses a truncate');
select throws_ok($$update public.weekly_award_setting_events set changed_by = null$$, '42501', null, 'only an account''s deletion forgets who changed something');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.disclaimer_draft_setting_events where settings = '{"version": 1}' and changed_by is null)
  + (select count(*)::int from public.weekly_award_setting_events where settings = '{"version": 1}' and changed_by is null),
  2, 'deleting the admin''s account keeps their changes, with no one named'
);
select is(
  (select count(*)::int from public.disclaimer_draft_setting_events where changed_by is null and settings ->> 'model' = 'openai/gpt-6-luna'),
  1, 'the log starts with the first settings'
);

select * from finish();
rollback;
