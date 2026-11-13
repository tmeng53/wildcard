-- Only our API reaches the data: the app's tokens (anon, authenticated) can't read or
-- write any table or reach the photo files, even through Supabase's own REST API.
begin;
select plan(15);

insert into auth.users (id, email) values ('a0000000-0000-0000-0000-000000000001', 'ann@example.com');
insert into storage.objects (bucket_id, name, owner_id) values
  ('check-in-photos', 'a0000000-0000-0000-0000-000000000001/run.jpg', 'a0000000-0000-0000-0000-000000000001');

-- Every table the migrations create, so a new one without the lock fails here.
select is(
  (select array_agg(tablename::text order by tablename) from pg_tables where schemaname = 'public'),
  array['admin_actions', 'admin_demo_accounts', 'admins', 'ai_consents', 'ai_usage', 'ai_usage_setting_events', 'ai_usage_settings', 'app_copy', 'app_copy_events', 'art_files', 'badges', 'broadcasts', 'campaigns', 'check_in_comment_mentions', 'check_in_comments', 'check_in_events', 'check_in_photos', 'check_in_reactions', 'check_in_squads', 'check_in_workouts', 'check_ins', 'coach_answer_mentions', 'coach_answers', 'coach_card_seen', 'coach_catalog_events', 'coach_challenge_answers', 'coach_challenge_completions', 'coach_files', 'coach_letter_tries', 'coach_letters', 'coach_member_note_deliveries', 'coach_member_note_reads', 'coach_member_notes', 'coach_notes', 'coach_replies', 'coach_reply_mentions', 'coach_setting_events', 'coach_settings', 'coach_wake_steps', 'coach_wakes', 'coaches', 'daily_push_setting_events', 'daily_push_settings', 'daily_pushes', 'disclaimer_dice', 'disclaimer_dice_events', 'disclaimer_draft_setting_events', 'disclaimer_draft_settings', 'feedback', 'feedback_adoptions', 'feedback_issues', 'fuel_goal_events', 'fuel_goals', 'grant_opens', 'grants', 'member_places', 'meme_events', 'memes', 'minimum_build', 'minimum_build_events', 'notice_reads', 'notices', 'nudges', 'piece_claims', 'piece_events', 'pieces', 'place_ratings', 'plan_templates', 'profile_events', 'profiles', 'push_devices', 'push_setting_events', 'push_settings', 'quick_reaction_events', 'quick_reactions', 'reward_catalog_events', 'reward_trigger_events', 'reward_triggers', 'rewards', 'saved_place_events', 'scene_catalog_events', 'scenes', 'sport_catalog_events', 'sport_categories', 'sport_picks', 'sports', 'squad_coach_events', 'squad_coaches', 'squad_events', 'squad_goal_suggestions', 'squad_languages', 'squad_members', 'squad_membership_events', 'squad_places', 'squad_scene_picks', 'squad_time_zones', 'squad_weekly_goals', 'squads', 'store_events', 'stores', 'switch_events', 'switch_previews', 'switches', 'teammate_push_setting_events', 'teammate_push_settings', 'teammate_pushes', 'vouchers', 'weather_days', 'week_stories', 'week_story_members', 'week_story_posts', 'week_summary_word_events', 'week_summary_words', 'weekly_award_setting_events', 'weekly_award_settings', 'weekly_award_winners', 'weekly_awards', 'weekly_plan_events', 'weekly_plans'],
  'these are all the tables'
);
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'row-level security is on for every table, so a stray grant still shows nothing'
);
select is(
  (select count(*)::int from pg_policies where schemaname = 'public'),
  0, 'no table has a policy that would let the app''s tokens in'
);
select is(
  (select count(*)::int from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated')),
  0, 'the app''s tokens have no privileges on any table or view'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
  0, 'the app''s tokens can''t call any function'
);
select ok(
  not has_schema_privilege('anon', 'public', 'usage') and not has_schema_privilege('authenticated', 'public', 'usage'),
  'the app''s tokens can''t use the public schema at all'
);
select ok(has_schema_privilege('service_role', 'public', 'usage'), 'the API''s server role can');

-- What a later migration adds is locked too.
create table public.later_table (id int);
create function public.later_function() returns int language sql as 'select 1';
select ok(
  not has_table_privilege('authenticated', 'public.later_table', 'select'),
  'a table a later migration adds gets no grants for the app''s tokens'
);
select ok(
  not has_function_privilege('anon', 'public.later_function()', 'execute')
  and not has_function_privilege('authenticated', 'public.later_function()', 'execute'),
  'a function a later migration adds can''t be called by the app''s tokens'
);
drop function public.later_function();
drop table public.later_table;

select is_empty(
  $$select 1 from storage.buckets where id = 'check-in-photos' and public$$,
  'the photos bucket is private'
);

-- An extension Supabase installs into public grants the app's roles access to its
-- functions; the schema lock still keeps them out.
create extension pg_trgm schema public;
select set_config('role', 'anon', true);
select throws_ok(
  'select public.show_limit()', '42501', null,
  'an extension installed into public later still can''t be reached by the app''s tokens'
);
select set_config('role', 'postgres', true);
drop extension pg_trgm;

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok(
  'select * from public.check_ins', '42501', null, 'a signed-in token can''t read check-ins'
);
select throws_ok(
  $$insert into public.squads (name, created_by) values ('早八跑团', 'a0000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a signed-in token can''t create a squad'
);
select throws_ok(
  $$insert into public.admins (member_id) values ('a0000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a signed-in token can''t make itself an admin'
);
select is_empty(
  $$select 1 from storage.objects where bucket_id = 'check-in-photos'$$,
  'a signed-in token can''t see photo files, even its own; the API signs URLs'
);

select * from finish();
rollback;
