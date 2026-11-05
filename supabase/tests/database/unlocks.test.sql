-- What members unlock: the rules are logged and never deleted, and a member's unlocks are
-- append-only until their account goes.
begin;
select plan(23);

insert into auth.users (id, email) values ('e0000000-0000-0000-0000-000000000001', 'una@example.com');

select is(
  (select count(*)::int from public.unlock_rules where kind <> 'piece'), 19,
  'a rule for each store and prop that is not a starter'
);
select is(
  (select count(*)::int from public.unlock_rules where kind = 'piece'), 57,
  'a rule for each piece the second wardrobe, the store specials and POWDER DAY added'
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

-- Gifts from a coach: a pool of pieces no store sells, logged and never deleted, and what each
-- member was given, append-only.
insert into public.gift_pieces (piece_id) values ('gift-scarf');
update public.gift_pieces set offered = false where piece_id = 'gift-scarf';
update public.gift_pieces set offered = false where piece_id = 'gift-scarf';
select is(
  (select array_agg(op order by id) from public.gift_piece_events where value ->> 'piece_id' = 'gift-scarf'),
  array['INSERT', 'UPDATE'], 'a gift piece''s change is logged once, and a save that changed nothing is not'
);
select throws_ok(
  $$insert into public.gift_pieces (piece_id) values ('Scarf')$$, '23514', null, 'a gift piece has a piece id'
);
select throws_ok(
  $$delete from public.gift_pieces$$, '42501', null, 'a gift piece is never deleted'
);
select throws_ok($$delete from public.gift_piece_events$$, '42501', null, 'the gift pool log refuses a delete');

insert into public.coach_gifts (member_id, piece_id, coach_id, squad_id)
values ('e0000000-0000-0000-0000-000000000001', 'gift-scarf', (select id from public.coaches limit 1),
  'e2000000-0000-0000-0000-000000000001');
select throws_ok(
  $$update public.coach_gifts set given_at = now() - interval '1 day'$$, '42501', null, 'a gift is never changed'
);
select throws_ok($$delete from public.coach_gifts$$, '42501', null, 'a gift is never taken back');
select throws_ok(
  $$insert into public.coach_gifts (member_id, piece_id, coach_id, squad_id)
    values ('e0000000-0000-0000-0000-000000000001', 'gift-nowhere', (select id from public.coaches limit 1),
      'e2000000-0000-0000-0000-000000000001')$$,
  '23503', null, 'a gift is a piece in the pool'
);

-- 领取: only a piece the member unlocked, and never undone.
insert into public.member_unlocks (member_id, kind, item_id, sports, after, given_by, unlocked_at)
values ('e0000000-0000-0000-0000-000000000001', 'piece', 'lap-bib', '{run,walk}', 5,
  'e0000000-0000-0000-0000-000000000001', now());
insert into public.piece_claims (member_id, piece_id) values ('e0000000-0000-0000-0000-000000000001', 'lap-bib');
select throws_ok(
  $$insert into public.piece_claims (member_id, piece_id) values ('e0000000-0000-0000-0000-000000000001', 'lap-vest')$$,
  '23503', null, 'a claim is of a piece the member unlocked'
);
select throws_ok($$delete from public.piece_claims$$, '42501', null, 'a claim is never taken back');
select throws_ok(
  $$update public.piece_claims set claimed_at = now() - interval '1 day'$$, '42501', null, 'a claim is never changed'
);

delete from auth.users where id = 'e0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.member_unlocks) + (select count(*)::int from public.coach_gifts)
    + (select count(*)::int from public.piece_claims), 0,
  'deleting the account takes its unlocks, gifts and claims'
);

select * from finish();
rollback;
