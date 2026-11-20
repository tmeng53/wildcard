-- A squad's own places: kept as added, until the squad ends or the adder deletes their account.
begin;
select plan(11);

insert into auth.users (id, email) values
  ('b1000000-0000-4000-8000-000000000001', 'mia@example.com'),
  ('b1000000-0000-4000-8000-000000000002', 'leo@example.com');
insert into public.squads (id, name, invite_code)
  values ('b2000000-0000-4000-8000-000000000001', 'squad', 'squad-places-test');

select lives_ok($$insert into public.squad_places (id, squad_id, added_by, name, kind, latitude, longitude, added_at)
  values ('b3000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001', '楼下公园', 'outdoor', 40.7, -73.9, now())$$,
  'a member adds a place for the squad');
select throws_ok($$insert into public.squad_places (id, squad_id, name, kind, latitude, longitude, added_at)
  values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001', 'x', 'gym', 0, 0, now())$$,
  '23502', null, 'a place names who added it');
select throws_ok($$insert into public.squad_places (id, squad_id, added_by, name, kind, latitude, longitude, added_at)
  values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002', '', 'gym', 0, 0, now())$$,
  '23514', null, 'a place has a name');
select throws_ok($$insert into public.squad_places (id, squad_id, added_by, name, kind, latitude, longitude, added_at)
  values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002', 'x', 'bar', 0, 0, now())$$,
  '23514', null, 'a place is food, gym or outdoor');
select throws_ok($$update public.squad_places set name = 'y'$$, '42501', null, 'a place is never changed');
select throws_ok($$delete from public.squad_places$$, '42501', null, 'a place is never removed');
select throws_ok($$truncate public.squad_places$$, '42501', null, 'the squad''s places are never emptied');

select is((select to_regclass('public.place_ratings')), null, 'places have no scores');

insert into public.squad_places (id, squad_id, added_by, name, kind, latitude, longitude, added_at)
  values ('b3000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002', '公司食堂', 'food', 40.75, -73.99, now());

-- The adder's account going takes their places, and only theirs.
delete from auth.users where id = 'b1000000-0000-4000-8000-000000000001';
select is((select string_agg(name, ',') from public.squad_places), '公司食堂',
  'a deleted account''s places go with it');
select throws_ok($$update public.squad_places set added_by = null$$, '42501', null,
  'who added a place is never cleared');
-- The squad's end takes its places.
delete from public.squads where id = 'b2000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.squad_places), 0, 'the squad''s end takes its places');

select * from finish();
rollback;
