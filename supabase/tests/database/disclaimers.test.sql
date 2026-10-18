-- A member posts at most one 今日免责声明 a day.
begin;
select plan(5);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com');

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.disclaimer(id uuid, day_offset int) returns void language sql as $$
  insert into public.check_ins (id, day, kind, payload, version) values
    (id, (now() at time zone 'UTC')::date + day_offset, 'disclaimer', '{"text":"下雨了"}', 1);
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select pg_temp.disclaimer('11111111-1111-1111-1111-111111111111', 0);
select throws_ok(
  $$select pg_temp.disclaimer(gen_random_uuid(), 0)$$,
  '23505', null, 'a second 免责声明 on the same day is refused'
);
select lives_ok(
  $$insert into public.check_ins (id, day, kind, payload, version) values
    (gen_random_uuid(), (now() at time zone 'UTC')::date, 'trained', '{"sport":"run","minutes":30}', 1)$$,
  'other kinds on that day are still fine'
);
select lives_ok(
  $$select pg_temp.disclaimer(gen_random_uuid(), 1)$$,
  'the next day gets its own 免责声明'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select lives_ok(
  $$select pg_temp.disclaimer(gen_random_uuid(), 0)$$,
  'another member posts their own 免责声明 the same day'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
delete from public.check_ins where id = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select pg_temp.disclaimer(gen_random_uuid(), 0)$$,
  'deleting the day''s 免责声明 lets the member post a new one'
);

select * from finish();
rollback;
