-- What members can get: each reward's triggers are logged and never deleted, and a member's grants
-- (by training, from a coach, from the team) are append-only until their account goes.
begin;
select plan(34);

insert into auth.users (id, email) values ('e0000000-0000-0000-0000-000000000001', 'una@example.com');

-- Counted from the seed, however many stores, props and pieces it holds today.
select ok(
  (select count(*) > 0 and bool_and(after >= 1) from public.reward_triggers
    where kind = 'training' and reward_kind <> 'piece'),
  'a training trigger for each store and prop that is not a starter (the props'' retired)'
);
select ok(
  (select count(*) > 0 and bool_and(after >= 1) from public.reward_triggers
    where kind = 'training' and reward_kind = 'piece'),
  'a training trigger for each piece the second wardrobe, the store specials and POWDER DAY added'
);
select ok(
  (select count(*) > 0 and bool_and(not offered) from public.reward_triggers
    where kind = 'training' and reward_kind = 'prop'),
  'every prop''s rule is retired: props are everyone''s'
);
select ok(
  (select bool_and(offered) from public.reward_triggers
    where kind = 'training' and reward_kind <> 'prop'),
  'the stores'' and pieces'' rules still count'
);
select throws_ok(
  $$insert into public.rewards (kind, id) values ('piece', 'Lap Bib')$$,
  '23514', null, 'a piece has a piece id'
);
select throws_ok(
  $$insert into public.rewards (kind, id) values ('store', 'lap-bib')$$,
  '23514', null, 'a store or prop keeps its catalog id'
);
select throws_ok(
  $$delete from public.rewards where id = 'deuce'$$, '42501', null, 'a reward is never removed'
);
select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind) values ('store', 'nowhere', 'team')$$,
  '23503', null, 'a trigger is of a reward'
);
select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind) values ('store', 'deuce', 'coach')$$,
  '23514', null, 'a coach gives only pieces'
);
select throws_ok(
  $$insert into public.reward_triggers (reward_kind, reward_id, kind, after) values ('prop', 'racket', 'team', 3)$$,
  '23514', null, 'only a training trigger counts check-ins'
);

update public.reward_triggers set after = 4 where reward_kind = 'store' and reward_id = 'deuce';
update public.reward_triggers set after = 4 where reward_kind = 'store' and reward_id = 'deuce';
select is(
  (select array_agg(op order by id) from public.reward_trigger_events
    where value ->> 'reward_id' = 'deuce' and not value ? 'replaces'),
  array['UPDATE'], 'a change is logged once, and a save that changed nothing is not'
);
select ok(
  (select count(*) > 0 from public.reward_trigger_events
    where value ->> 'item_id' = 'deuce' and value ->> 'replaces' = 'unlock_rule_events'),
  'the log keeps what the rules'' log held'
);
select throws_ok(
  $$delete from public.reward_triggers where reward_id = 'deuce'$$, '42501', null, 'a trigger is never deleted'
);
select throws_ok(
  $$update public.reward_triggers set counts_from = now() - interval '1 year' where reward_id = 'deuce'$$,
  '42501', null, 'a trigger keeps the time it counts from'
);
select throws_ok(
  $$update public.reward_triggers set kind = 'team' where reward_id = 'deuce'$$,
  '42501', null, 'a trigger keeps its way'
);
select throws_ok($$delete from public.reward_trigger_events$$, '42501', null, 'the trigger log refuses a delete');

insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, check_in_id, at)
values ('e0000000-0000-0000-0000-000000000001', 'store', 'deuce', 'training', '{tennis}', 3,
  'e1000000-0000-0000-0000-000000000001', now());
select throws_ok($$update public.grants set after = 1$$, '42501', null, 'a grant is never changed');
select throws_ok($$delete from public.grants$$, '42501', null, 'a grant is never taken back');
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, check_in_id, at)
    values ('e0000000-0000-0000-0000-000000000001', 'store', 'nowhere', 'training', '{}', 1,
      'e1000000-0000-0000-0000-000000000002', now())$$,
  '23503', null, 'a grant is of a reward'
);
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, at)
    values ('e0000000-0000-0000-0000-000000000001', 'prop', 'racket', 'training', '{}', 1, now())$$,
  '23514', null, 'a training grant names the check-in that earned it'
);
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, at)
    values ('e0000000-0000-0000-0000-000000000001', 'prop', 'racket', 'team', now())$$,
  '23514', null, 'a team grant names the admin who gave it'
);

-- Gifts from a coach: pieces with a coach trigger, and what each member was given, append-only.
insert into public.rewards (kind, id) values ('piece', 'gift-scarf'), ('piece', 'gift-cap'),
  ('piece', 'gift-scarf-2');
insert into public.reward_triggers (reward_kind, reward_id, kind) values
  ('piece', 'gift-scarf', 'coach'), ('piece', 'gift-cap', 'coach'), ('piece', 'gift-scarf-2', 'coach');
update public.reward_triggers set offered = false where reward_id = 'gift-scarf';
update public.reward_triggers set offered = false where reward_id = 'gift-scarf';
select is(
  (select array_agg(op order by id) from public.reward_trigger_events where value ->> 'reward_id' = 'gift-scarf'),
  array['INSERT', 'UPDATE'], 'a gift piece''s change is logged once, and a save that changed nothing is not'
);
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, coach_id, given_by, at)
    values ('e0000000-0000-0000-0000-000000000001', 'piece', 'gift-scarf', 'coach',
      (select id from public.coaches limit 1), 'coach', now())$$,
  '23514', null, 'a coach''s gift names the squad it was coaching'
);

-- One gift a member a week, whoever gives it; opened once, and the opening stays.
insert into public.grants (member_id, reward_kind, reward_id, via, coach_id, squad_id, week_from,
  given_by, at)
values ('e0000000-0000-0000-0000-000000000001', 'piece', 'gift-cap', 'coach',
  (select id from public.coaches limit 1), 'e2000000-0000-0000-0000-000000000001',
  '2026-11-02T05:00:00Z', 'coach', now());
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, coach_id, squad_id, week_from,
      given_by, admin_id, at)
    values ('e0000000-0000-0000-0000-000000000001', 'piece', 'gift-scarf-2', 'coach',
      (select id from public.coaches limit 1), 'e2000000-0000-0000-0000-000000000001',
      '2026-11-02T05:00:00Z', 'admin', 'e0000000-0000-0000-0000-000000000009', now())$$,
  '23505', null, 'one gift a member a week'
);
select throws_ok(
  $$insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, admin_id, at)
    values ('e0000000-0000-0000-0000-000000000001', 'piece', 'gift-cap', 'team', '{}', 1,
      'e0000000-0000-0000-0000-000000000009', now())$$,
  '23505', null, 'a member gets each reward once'
);
insert into public.grant_opens (grant_id, worn)
select id, true from public.grants where reward_id = 'gift-cap';
select throws_ok(
  $$insert into public.grant_opens (grant_id, worn)
    select id, false from public.grants where reward_id = 'gift-cap'$$,
  '23505', null, 'a gift is opened once'
);
select throws_ok($$update public.grant_opens set worn = false$$, '42501', null, 'an opening stays');
select throws_ok(
  $$insert into public.grant_opens (grant_id, worn) values (-1, true)$$,
  '23503', null, 'only a gift the member was given is opened'
);

-- An admin who gave a gift can still delete their account: the gift stays as it was.
insert into auth.users (id, email) values ('e0000000-0000-0000-0000-000000000009', 'ada@example.com');
insert into public.grants (member_id, reward_kind, reward_id, via, sports, after, admin_id, at)
values ('e0000000-0000-0000-0000-000000000001', 'prop', 'racket', 'team', '{tennis,squash}', 1,
  'e0000000-0000-0000-0000-000000000009', now());
delete from auth.users where id = 'e0000000-0000-0000-0000-000000000009';
select is(
  (select admin_id::text from public.grants where reward_id = 'racket'),
  'e0000000-0000-0000-0000-000000000009', 'deleting the admin keeps the grant as it was'
);

-- 领取: of a listed piece, and never undone.
insert into public.piece_claims (member_id, piece_id) values ('e0000000-0000-0000-0000-000000000001', 'lap-bib');
select throws_ok(
  $$insert into public.piece_claims (member_id, piece_id) values ('e0000000-0000-0000-0000-000000000001', 'no-such-piece')$$,
  '23503', null, 'a claim is of a listed piece'
);
select throws_ok($$delete from public.piece_claims$$, '42501', null, 'a claim is never taken back');
select throws_ok(
  $$update public.piece_claims set claimed_at = now() - interval '1 day'$$, '42501', null, 'a claim is never changed'
);

delete from auth.users where id = 'e0000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::int from public.grants) + (select count(*)::int from public.grant_opens)
    + (select count(*)::int from public.piece_claims), 0,
  'deleting the account takes its grants, openings and claims'
);
select hasnt_table('public', 'member_unlocks', 'grants replace member_unlocks and coach_gifts');

select * from finish();
rollback;
