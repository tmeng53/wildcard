-- What the database keeps true about blocks and reports however the API writes them.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000001', 'di@example.com'),
  ('d0000000-0000-0000-0000-000000000002', 'ed@example.com');

select lives_ok(
  $$insert into public.member_blocks (member_id, other_id, kind)
    values ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'blocked')$$,
  'a block is logged'
);
select throws_ok(
  $$insert into public.member_blocks (member_id, other_id, kind)
    values ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'blocked')$$,
  '23514', null, 'nobody blocks themselves'
);
select throws_ok(
  $$update public.member_blocks set kind = 'unblocked'$$, null, null, 'the block log is never changed'
);
select throws_ok($$delete from public.member_blocks$$, null, null, 'the block log is never deleted from');

select lives_ok(
  $$insert into public.content_reports (id, member_id, kind, check_in_id, item_id, author_id, snapshot)
    values ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'comment',
      'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002',
      'd0000000-0000-0000-0000-000000000002', '{"version":1,"words":"走开"}')$$,
  'a report keeps what the reporter saw'
);
select throws_ok(
  $$insert into public.content_reports (id, member_id, kind, check_in_id, item_id, snapshot)
    values ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'comment',
      'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', '{"version":1}')$$,
  '23505', null, 'the same thing is reported once by a member'
);
select throws_ok(
  $$insert into public.content_reports (id, member_id, kind, check_in_id, snapshot)
    values ('e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', 'checkIn',
      'f0000000-0000-0000-0000-000000000003', '{}')$$,
  '23514', null, 'the snapshot carries its version'
);
select throws_ok(
  $$update public.content_reports set snapshot = '{"version":1}'$$, null, null, 'a report is never changed'
);

-- The other account going takes the block and the report about their words with it.
delete from auth.users where id = 'd0000000-0000-0000-0000-000000000002';
select is(
  (select count(*)::int from public.member_blocks) + (select count(*)::int from public.content_reports),
  0, 'deleting an account removes the blocks and reports that name it'
);

select * from finish();
rollback;
