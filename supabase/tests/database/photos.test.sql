-- Check-in photos: members upload only into their own folder, and a photo is seen
-- only by its owner and by members of the squads its check-in was sent to.
begin;
select plan(8);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'cy@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

select is(
  (select public from storage.buckets where id = 'check-in-photos'), false,
  'the photos bucket is private'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('check-in-photos', 'a0000000-0000-0000-0000-000000000001/run.jpg', 'a0000000-0000-0000-0000-000000000001')$$,
  'a member uploads into their own folder'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('check-in-photos', 'b0000000-0000-0000-0000-000000000002/run.jpg', 'a0000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a member can''t upload into someone else''s folder'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select is_empty(
  $$select 1 from storage.objects where bucket_id = 'check-in-photos'$$,
  'a squad-mate doesn''t see a photo before it is on a check-in sent to the squad'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
insert into public.check_ins (id, day, kind, payload, version) values
  ('11111111-1111-1111-1111-111111111111', current_date, 'trained',
   '{"sport":"run","minutes":30,"photo":{"path":"a0000000-0000-0000-0000-000000000001/run.jpg"}}', 1);
insert into public.check_in_squads (check_in_id, squad_id) values
  ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001');

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select results_eq(
  $$select name from storage.objects where bucket_id = 'check-in-photos'$$,
  array['a0000000-0000-0000-0000-000000000001/run.jpg'],
  'a squad-mate sees the photo on a check-in sent to their squad'
);
-- The Storage API sets this flag before it deletes; the policies decide which rows go.
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/run.jpg';

select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select is_empty(
  $$select 1 from storage.objects where bucket_id = 'check-in-photos'$$,
  'someone outside the squad doesn''t see it'
);

select set_config('role', 'postgres', true);
select isnt_empty(
  $$select 1 from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/run.jpg'$$,
  'a squad-mate can''t delete the photo'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
delete from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/run.jpg';
select set_config('role', 'postgres', true);
select is_empty(
  $$select 1 from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/run.jpg'$$,
  'the member deletes their own photo'
);

select * from finish();
rollback;
