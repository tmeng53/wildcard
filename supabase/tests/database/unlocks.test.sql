-- What members unlock: the rules are logged and never deleted, and a member's unlocks are
-- append-only until their account goes.
begin;
select plan(13);

insert into auth.users (id, email) values ('e0000000-0000-0000-0000-000000000001', 'una@example.com');

select is(
  (select count(*)::int from public.unlock_rules where kind <> 'piece'), 13,
  'a rule for each store and prop that is not a starter'
);
select is(
  (select count(*)::int from public.unlock_rules where kind = 'piece'), 44,
  'a rule for each piece the second wardrobe and the store specials added'
);
select throws_ok(
  $$insert into public.unlock_rules (kind, item_id, after) values ('piece', 'Lap Bib', 3)$$,
  '23514', null, 'a piece has a piece id'
);
select throws_ok(
  $$insert into public.unlock_rules (kind, item_id, after) values ('store', 'lap-bib', 3)$$,
  '23514', null, 'a store or prop keeps its catalog id'
);

update public.unlock_rules set after = 4 where kind = 'store' and item_id = 'deuce';
update public.unlock_rules set after = 4 where kind = 'store' and item_id = 'deuce';
select is(
  (select array_agg(op order by id) from public.unlock_rule_events where value ->> 'item_id' = 'deuce'),
  array['INSERT', 'UPDATE'], 'a change is logged once, and a save that changed nothing is not'
);
select throws_ok(
  $$delete from public.unlock_rules where item_id = 'deuce'$$, '42501', null, 'a rule is never deleted'
);
select throws_ok(
  $$update public.unlock_rules set counts_from = now() - interval '1 year' where item_id = 'deuce'$$,
  '42501', null, 'a rule keeps the time it counts from'
);
select throws_ok($$delete from public.unlock_rule_events$$, '42501', null, 'the rule log refuses a delete');

insert into public.member_unlocks (member_id, kind, item_id, sports, after, check_in_id, unlocked_at)
values ('e0000000-0000-0000-0000-000000000001', 'store', 'deuce', '{tennis}', 3,
  'e1000000-0000-0000-0000-000000000001', now());
select throws_ok(
  $$update public.member_unlocks set after = 1$$, '42501', null, 'an unlock is never changed'
);
select throws_ok($$delete from public.member_unlocks$$, '42501', null, 'an unlock is never taken back');
select throws_ok(
  $$insert into public.member_unlocks (member_id, kind, item_id, sports, after, check_in_id, unlocked_at)
    values ('e0000000-0000-0000-0000-000000000001', 'store', 'nowhere', '{}', 1,
      'e1000000-0000-0000-0000-000000000002', now())$$,
  '23503', null, 'an unlock names a rule'
);
select throws_ok(
  $$insert into public.member_unlocks (member_id, kind, item_id, sports, after, unlocked_at)
    values ('e0000000-0000-0000-0000-000000000001', 'prop', 'racket', '{}', 1, now())$$,
  '23514', null, 'an unlock was earned by a check-in or given by an admin'
);

delete from auth.users where id = 'e0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.member_unlocks), 0, 'deleting the account takes its unlocks'
);

select * from finish();
rollback;
