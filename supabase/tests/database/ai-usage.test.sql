-- Every model call, counted to its squad and member: a log that only grows, until the squad ends
-- or the member's account goes (which forgets only who); and one row of prices and caps, logged.
begin;
select plan(17);

insert into auth.users (id, email) values
  ('a1000000-0000-4000-8000-000000000001', 'mia@example.com'),
  ('a1000000-0000-4000-8000-000000000002', 'admin@example.com');
insert into public.squads (id, name, invite_code)
  values ('a2000000-0000-4000-8000-000000000001', 'squad', 'ai-usage-test');

insert into public.ai_usage
  (feature, squad_id, member_id, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros)
values
  ('disclaimer-drafts', 'a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
    'openai/gpt-6-luna', 1, 800, 0, 96, 128),
  ('coach-wake', 'a2000000-0000-4000-8000-000000000001', null, 'openai/gpt-6-luna', 2, 12000, 10000, 800, 700),
  -- A member without a squad: their call is counted to no squad.
  ('disclaimer-drafts', null, 'a1000000-0000-4000-8000-000000000001', 'anthropic/claude-haiku-5-5', 1, 1, 0, 1, 1);

select throws_ok($$insert into public.ai_usage (feature, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros)
  values ('poems', 'openai/gpt-6-luna', 1, 1, 0, 1, 1)$$, '23514', null, 'a call is for a feature we know');
select throws_ok($$insert into public.ai_usage (feature, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros)
  values ('coach-wake', 'gemini/flash', 1, 1, 0, 1, 1)$$, '23514', null, 'a model names a provider the API knows');
select throws_ok($$insert into public.ai_usage (feature, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros)
  values ('coach-wake', 'openai/gpt-6-luna', 1, 500, 501, 0, 0)$$, '23514', null, 'never more cached input than input');
select throws_ok($$insert into public.ai_usage (feature, model, requests, input_tokens, cached_input_tokens, output_tokens, cost_micros)
  values ('coach-wake', 'openai/gpt-6-luna', 1, 1, 0, 1, -1)$$, '23514', null, 'a cost is never negative');
select throws_ok($$update public.ai_usage set cost_micros = 0$$, '42501', null, 'a call is never changed');
select throws_ok($$update public.ai_usage set member_id = null$$, '42501', null, 'a live member stays named');
select throws_ok($$delete from public.ai_usage$$, '42501', null, 'a call is never removed');
select throws_ok($$truncate public.ai_usage$$, '42501', null, 'the ledger is never emptied');

-- A deleted account leaves its calls to its squad, unnamed.
delete from auth.users where id = 'a1000000-0000-4000-8000-000000000001';
select is(
  (select array_agg(feature || ':' || coalesce(squad_id::text, '-') || ':' || coalesce(member_id::text, '-') order by id)
    from public.ai_usage where cost_micros in (128, 700, 1)),
  array['disclaimer-drafts:a2000000-0000-4000-8000-000000000001:-', 'coach-wake:a2000000-0000-4000-8000-000000000001:-', 'disclaimer-drafts:-:-'],
  'a deleted account''s calls stay, with no one named'
);
-- The squad's end takes its calls; one counted to no squad stays.
delete from public.squads where id = 'a2000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.ai_usage where cost_micros in (128, 700, 1)), 1,
  'the squad''s end takes its calls');

-- The settings: one row, every change logged.
select is((select count(*)::int from public.ai_usage_settings), 1, 'the AI usage settings start with their row');
select throws_ok($$delete from public.ai_usage_settings$$, '42501', null, 'the settings keep their row');
select throws_ok($$truncate public.ai_usage_settings$$, '42501', null, 'the settings are never emptied');
select throws_ok($$update public.ai_usage_settings set squad_daily_cap_micros = -1$$, '23514', null, 'a cap is never negative');
insert into public.ai_usage_setting_events (changed_by, settings)
  values ('a1000000-0000-4000-8000-000000000002', '{"version": 1}');
select throws_ok($$update public.ai_usage_setting_events set settings = '{"version": 2}'$$, '42501', null, 'the settings log refuses an update');
select throws_ok($$delete from public.ai_usage_setting_events$$, '42501', null, 'the settings log refuses a delete');
-- The migration logged the first settings, priced the way the coach's were.
select ok(
  (select settings -> 'prices' ? 'openai/gpt-6-luna' from public.ai_usage_setting_events where changed_by is null order by id limit 1),
  'the log starts with the first settings, every model a setting names priced'
);

select * from finish();
rollback;
