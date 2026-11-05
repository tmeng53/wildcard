-- Art files: the public bucket takes only the art's types, and the list of files is its own log.
begin;
select plan(6);

select is(
  (select public from storage.buckets where id = 'art'), true, 'the art bucket is public'
);

insert into public.art_files (path, sha256, size, changed_by) values
  ('avatar/art/top/winter-scarf/torso.svg', repeat('a', 64), 120, 'e0000000-0000-0000-0000-000000000001');
insert into public.art_files (path, changed_by) values
  ('avatar/art/top/winter-scarf/torso.svg', 'e0000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.art_files), 2, 'a path going back to the bundled file is a new row');

select throws_ok(
  $$update public.art_files set size = 1$$, '42501', null, 'a row is never changed'
);
select throws_ok($$delete from public.art_files$$, '42501', null, 'a row is never deleted');
select throws_ok(
  $$insert into public.art_files (path, sha256, size, changed_by)
    values ('avatar/../secrets.json', repeat('b', 64), 1, 'e0000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'a path never leaves the art tree'
);
select throws_ok(
  $$insert into public.art_files (path, sha256, changed_by)
    values ('scenes/ski-day@3x.png', repeat('c', 64), 'e0000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'a file has its size'
);

select * from finish();
rollback;
