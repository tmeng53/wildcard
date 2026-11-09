-- What the database keeps true about the scenes list however it is edited.
begin;
select plan(14);

select is(
  (select array_agg(id order by position) from public.scenes),
  array['track', 'pool', 'gym', 'tennis', 'climbing', 'ski'],
  'the first list is the five scenes and the winter ski scene, in the picker''s order'
);
select is(
  (select (s.mode, s.window_start, s.window_end)::text
     from public.scenes c join public.switches s on s.id = c.switch_id where c.id = 'ski'),
  '(schedule,11-15,03-31)',
  'the ski scene follows the winter switch, on from November 15 to March 31'
);
select is(
  (select count(*)::int from public.scene_catalog_events),
  6,
  'seeding the list logged a row for each scene'
);
select throws_ok(
  $$delete from public.scenes where id = 'ski'$$,
  '42501', null, 'a scene is never deleted, since picks and frozen stories name it'
);
select throws_ok(
  $$truncate public.scenes cascade$$,
  '42501', null, 'a truncate cannot wipe the scenes, since it would skip the log'
);
select throws_ok(
  $$update public.scenes set id = 'skiing' where id = 'ski'$$,
  '42501', null, 'a scene keeps its id'
);
select throws_ok(
  $$update public.switches set window_end = null where id = 'winter'$$,
  '23514', null, 'a window has both ends or none'
);
select throws_ok(
  $$update public.switches set window_start = null, window_end = null where id = 'winter'$$,
  '23514', null, 'a switch on a schedule has its days'
);
select throws_ok(
  $$delete from public.switches where id = 'winter'$$,
  '42501', null, 'a switch is never deleted'
);
update public.switches set mode = 'on' where id = 'winter';
update public.switches set mode = 'on' where id = 'winter';
select is(
  (select count(*)::int from public.switch_events where value ->> 'id' = 'winter'),
  2,
  'a switch logs its seeding and each change, once'
);
select throws_ok(
  $$delete from public.switch_events$$,
  '42501', null, 'the switch log only grows'
);

update public.scenes set offered = false where id = 'ski';
update public.scenes set offered = false where id = 'ski';
select is(
  (select count(*)::int from public.scene_catalog_events where op = 'UPDATE'),
  1,
  'a change is logged once, and a save that changed nothing is not'
);
select throws_ok(
  $$delete from public.scene_catalog_events$$,
  '42501', null, 'the log only grows'
);
select fk_ok(
  'public', 'squad_scene_picks', 'scene', 'public', 'scenes', 'id',
  'a pick names a listed scene'
);

select * from finish();
rollback;
