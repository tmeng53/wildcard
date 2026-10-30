-- What the database keeps true about the sports list however it is edited.
begin;
select plan(16);

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
  $$truncate public.sports cascade$$,
  '42501', null, 'a truncate cannot wipe the sports, since it would skip the log'
);
select throws_ok(
  $$truncate public.sport_categories cascade$$,
  '42501', null, 'nor the categories'
);
select throws_ok(
  $$truncate public.sport_picks$$,
  '42501', null, 'nor the short lists'
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
select throws_ok(
  $$update public.sports set short_name_en = 'Jog' where id = 'run'$$,
  '23514', null, 'a short name comes in all three languages or none'
);
select is(
  (select short_name_en from public.sports where id = 'tableTennis'),
  'Ping pong',
  'a long name has a shorter one for cards'
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

-- Moving a tab swaps places in one statement; the places are checked at its end.
select lives_ok(
  $$ update public.sport_categories set position = case id when 'runWalk' then 2 else 1 end
     where id in ('runWalk', 'strength') $$,
  'two tabs swap places in one statement'
);

select * from finish();
rollback;
