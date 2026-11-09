-- The app copy: one row of lines put over the app's catalog, never deleted, and a log that only
-- grows, except that it forgets which admin made a change once that admin deletes their account.
begin;
select plan(7);

insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000005', 'admin@example.com');
insert into public.app_copy_events (changed_by, copy) values
  ('d0000000-0000-0000-0000-000000000005', '{"version": 1}');

select is((select entries from public.app_copy), '{}'::jsonb, 'nothing is put to begin with');
select throws_ok($$delete from public.app_copy$$, '42501', null, 'the copy keeps its row');
select throws_ok($$insert into public.app_copy (only_row) values (false)$$, '23514', null, 'there is only one row of copy');
select throws_ok($$update public.app_copy set entries = '[]'$$, '23514', null, 'the copy is lines by key');
select throws_ok($$update public.app_copy_events set copy = '{"version": 2}'$$, '42501', null, 'the log refuses an update');
select throws_ok($$truncate public.app_copy_events$$, '42501', null, 'the log refuses a truncate');

delete from auth.users where id = 'd0000000-0000-0000-0000-000000000005';
select is(
  (select count(*)::int from public.app_copy_events where changed_by is null and copy = '{"version": 1}'),
  1, 'the log keeps the deleted admin''s change, with no one named'
);

select * from finish();
rollback;
