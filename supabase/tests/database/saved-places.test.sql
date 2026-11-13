-- What the database keeps true about a member's saved places however the API writes them.
begin;
select plan(8);

insert into auth.users (id, email) values ('c0000000-0000-0000-0000-000000000001', 'cy@example.com');

select lives_ok(
  $$insert into public.saved_place_events (member_id, place_key, kind, place, note)
    values ('c0000000-0000-0000-0000-000000000001', 'apple:I6FA1B2C3D4E5F6', 'saved',
      '{"version":1,"place":{"name":"Equinox","latitude":40.7,"longitude":-73.9}}', '单车课')$$,
  'a save with its place and note is logged'
);
select lives_ok(
  $$insert into public.saved_place_events (member_id, place_key, kind)
    values ('c0000000-0000-0000-0000-000000000001', 'apple:I6FA1B2C3D4E5F6', 'removed')$$,
  'a removal is logged without a place'
);
select throws_ok(
  $$insert into public.saved_place_events (member_id, place_key, kind, place)
    values ('c0000000-0000-0000-0000-000000000001', 'apple:I6FA1B2C3D4E5F6', 'saved',
      '{"place":{"name":"Equinox","latitude":40.7,"longitude":-73.9}}')$$,
  '23514', null, 'stored place JSON carries its version'
);
select throws_ok(
  $$insert into public.saved_place_events (member_id, place_key, kind)
    values ('c0000000-0000-0000-0000-000000000001', 'apple:I6FA1B2C3D4E5F6', 'saved')$$,
  '23514', null, 'a save carries its place'
);
select throws_ok(
  $$insert into public.saved_place_events (member_id, place_key, kind)
    values ('c0000000-0000-0000-0000-000000000001', 'at:40.7,-73.9', 'removed')$$,
  '23514', null, 'a place is kept by its Apple Maps or squad place key'
);
select throws_ok(
  $$update public.saved_place_events set note = 'x'$$,
  null, null, 'the log is never changed'
);
select throws_ok(
  $$delete from public.saved_place_events$$,
  null, null, 'the log is never deleted from'
);

delete from auth.users where id = 'c0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.saved_place_events where member_id = 'c0000000-0000-0000-0000-000000000001'),
  0, 'deleting an account deletes its saved places'
);

select * from finish();
rollback;
