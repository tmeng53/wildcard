-- A squad's own places: kept as added, until the squad ends; the adder's account going forgets
-- only who added it.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('b1000000-0000-4000-8000-000000000001', 'mia@example.com');
insert into public.squads (id, name, invite_code)
  values ('b2000000-0000-4000-8000-000000000001', 'squad', 'squad-places-test');

select lives_ok($$insert into public.squad_places (id, squad_id, added_by, name, kind, latitude, longitude, added_at)
  values ('b3000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001', '楼下公园', 'outdoor', 40.7, -73.9, now())$$,
  'a member adds a place for the squad');
select throws_ok($$insert into public.squad_places (id, squad_id, name, kind, latitude, longitude, added_at)
  values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001', '', 'gym', 0, 0, now())$$,
  '23514', null, 'a place has a name');
select throws_ok($$insert into public.squad_places (id, squad_id, name, kind, latitude, longitude, added_at)
  values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001', 'x', 'bar', 0, 0, now())$$,
  '23514', null, 'a place is food, gym or outdoor');
select throws_ok($$update public.squad_places set name = 'y'$$, '42501', null, 'a place is never changed');
select throws_ok($$delete from public.squad_places$$, '42501', null, 'a place is never removed');
select throws_ok($$truncate public.squad_places$$, '42501', null, 'the squad''s places are never emptied');

select is((select to_regclass('public.place_ratings')), null, 'places have no scores');

-- The adder's account going leaves the place, with no one named.
delete from auth.users where id = 'b1000000-0000-4000-8000-000000000001';
select is((select coalesce(added_by::text, '-') || ':' || name from public.squad_places),
  '-:楼下公园', 'a deleted account''s place stays, with no one named');
-- The squad's end takes its places.
delete from public.squads where id = 'b2000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.squad_places), 0, 'the squad''s end takes its places');

select * from finish();
rollback;
