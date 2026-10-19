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
  array['admin_actions', 'admins', 'check_in_photos', 'check_in_squads', 'check_ins', 'memes', 'profiles', 'squad_members', 'squads', 'weekly_plans'],
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
