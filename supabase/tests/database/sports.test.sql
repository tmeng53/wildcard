-- What the database keeps true about the sports list however it is edited.
begin;
select plan(10);

select is((select count(*)::int from public.sports), 52, 'the first list has 52 sports');
select is(
  (select count(*)::int from public.sport_catalog_events),
  (select (select count(*) from public.sport_categories) + (select count(*) from public.sports)
    + (select count(*) from public.sport_picks))::int,
  'seeding the list logged a row for each row it added'
);

select throws_ok(
  $$delete from public.sports where id = 'run'$$,
  '42501', null, 'a sport is never deleted, since check-ins name it'
);
select throws_ok(
  $$update public.sports set id = 'running' where id = 'run'$$,
  '42501', null, 'a sport keeps its id'
);
select throws_ok(
  $$insert into public.sports (id, category_id, position, icon, name_zh_hans, name_en, name_zh_hant)
    values ('custom', 'runWalk', 99, 'figure.run', '其他', 'Other', '其他')$$,
  '23514', null, '`custom` is 其他, never a listed sport'
);
select throws_ok(
  $$insert into public.sports (id, category_id, position, icon, name_zh_hans, name_en, name_zh_hant)
    values ('quidditch', 'nowhere', 1, 'figure.run', '魁地奇', 'Quidditch', '魁地奇')$$,
  '23503', null, 'a sport is in a listed category'
);

-- A change is logged with its new value; a save that changed nothing is not.
update public.sports set offered = false where id = 'moving';
select is(
  (select value ->> 'offered' from public.sport_catalog_events order by id desc limit 1),
  'false',
  'retiring a sport is logged with its new value'
);
select is(
  (select count(*)::int from public.sport_catalog_events where kind = 'sports' and op = 'UPDATE'),
  1,
  'one row for that change'
);
update public.sports set offered = false where id = 'moving';
select is(
  (select count(*)::int from public.sport_catalog_events where kind = 'sports' and op = 'UPDATE'),
  1,
  'a save that changed nothing is not logged'
);

select throws_ok(
  $$delete from public.sport_catalog_events$$,
  '42501', null, 'the log only grows'
);

select * from finish();
rollback;
