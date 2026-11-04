-- What the database keeps true about the scenes list however it is edited.
begin;
select plan(10);

select is(
  (select array_agg(id order by position) from public.scenes),
  array['track', 'pool', 'gym', 'tennis', 'climbing', 'ski'],
  'the first list is the five scenes and the winter ski scene, in the picker''s order'
);
select is(
  (select (window_start, window_end)::text from public.scenes where id = 'ski'),
  '(11-15,03-31)',
  'the ski scene is open from November 15 to March 31'
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
  $$update public.scenes set window_end = null where id = 'ski'$$,
  '23514', null, 'a window has both ends or none'
);

update public.scenes set window_start = '12-01' where id = 'ski';
update public.scenes set window_start = '12-01' where id = 'ski';
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
