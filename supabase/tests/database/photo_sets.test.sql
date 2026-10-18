-- A check-in carries 1 to 3 photos, the first being the cover (contract `Photos`).
-- Each photo belongs to one check-in, and every one of them is locked and shared
-- the way a single photo is (photos.test.sql).
begin;
select plan(12);

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ann@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'bo@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'cy@example.com');
insert into public.squads (id, name, created_by) values
  ('5a000000-0000-0000-0000-000000000001', '早八跑团', 'a0000000-0000-0000-0000-000000000001');
insert into public.squad_members (squad_id, member_id) values
  ('5a000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002');
insert into storage.objects (bucket_id, name, owner_id)
select 'check-in-photos', 'a0000000-0000-0000-0000-000000000001/' || n || '.jpg', 'a0000000-0000-0000-0000-000000000001'
from unnest(array['1', '2', '3', '4']) n;

create function pg_temp.sign_in(member uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', member, 'role', 'authenticated')::text, true);
$$;

-- Ann's 练了 as the app encodes it, with these photos.
create function pg_temp.wire(id uuid, photos text[]) returns jsonb language sql as $$
  select jsonb_build_object(
    'version', 1, 'id', id, 'member', 'a0000000-0000-0000-0000-000000000001',
    'day', (now() at time zone 'UTC')::date,
    'createdAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'kind', 'trained',
    'training', jsonb_build_object(
      'sport', 'run', 'minutes', 30,
      'photos', (select jsonb_agg(jsonb_build_object('path', 'a0000000-0000-0000-0000-000000000001/' || p || '.jpg') order by o)
                 from unnest(photos) with ordinality as x (p, o))
    ),
    'audience', '["5a000000-0000-0000-0000-000000000001"]'::jsonb
  );
$$;

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$select public.create_check_in(pg_temp.wire(gen_random_uuid(), array['1', '2', '3', '4']))$$,
  '23514', null, 'a check-in has at most 3 photos'
);
select throws_ok(
  $$select public.create_check_in(jsonb_set(pg_temp.wire(gen_random_uuid(), array['1']), '{training,photos}', '[]'))$$,
  '23514', null, 'a check-in''s photos aren''t an empty list; with none, the key is left out'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire(gen_random_uuid(), array['1', '2', '1']))$$,
  '23514', null, 'a check-in lists each photo once'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire(gen_random_uuid(), array['1', 'not-uploaded']))$$,
  '23514', 'upload a check-in''s photos before saving it',
  'every photo is uploaded before the check-in is saved, not only the cover'
);
select throws_ok(
  $$select public.create_check_in(jsonb_set(pg_temp.wire(gen_random_uuid(), array['1']), '{training,photo}', '{"path":"a0000000-0000-0000-0000-000000000001/1.jpg"}') #- '{training,photos}')$$,
  '23514', null, 'the old single `photo` key is no longer accepted'
);

select lives_ok(
  $$select public.create_check_in(pg_temp.wire('11111111-1111-1111-1111-111111111111', array['3', '1', '2']))$$,
  'a member saves a check-in with 3 photos'
);
select is(
  (select check_in -> 'training' -> 'photos' from public.check_ins_wire),
  '[{"path":"a0000000-0000-0000-0000-000000000001/3.jpg"},{"path":"a0000000-0000-0000-0000-000000000001/1.jpg"},{"path":"a0000000-0000-0000-0000-000000000001/2.jpg"}]'::jsonb,
  'the photos read back in the order the member picked, cover first'
);
select throws_ok(
  $$select public.create_check_in(pg_temp.wire(gen_random_uuid(), array['4', '2']))$$,
  '23505', 'another check-in already uses this photo',
  'a photo that is the second on another check-in can''t be reused'
);

select pg_temp.sign_in('b0000000-0000-0000-0000-000000000002');
select results_eq(
  $$select name from storage.objects where bucket_id = 'check-in-photos' order by name$$,
  array['a0000000-0000-0000-0000-000000000001/1.jpg', 'a0000000-0000-0000-0000-000000000001/2.jpg',
        'a0000000-0000-0000-0000-000000000001/3.jpg'],
  'a squad-mate sees all three photos, and not the unused fourth'
);
select pg_temp.sign_in('c0000000-0000-0000-0000-000000000003');
select is_empty(
  $$select 1 from storage.objects where bucket_id = 'check-in-photos'$$,
  'someone outside the squad sees none of them'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/2.jpg';
select set_config('role', 'postgres', true);
select isnt_empty(
  $$select 1 from storage.objects where name = 'a0000000-0000-0000-0000-000000000001/2.jpg'$$,
  'a photo that isn''t the cover is locked too'
);

select pg_temp.sign_in('a0000000-0000-0000-0000-000000000001');
delete from public.check_ins where id = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.create_check_in(pg_temp.wire(gen_random_uuid(), array['2']))$$,
  'deleting a check-in frees all of its photos'
);

select * from finish();
rollback;
