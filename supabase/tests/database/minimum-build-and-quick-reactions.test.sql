-- The minimum build and the quick reactions: one row each, never deleted, kept in shape, and
-- logs that only grow.
begin;
select plan(10);

select is((select build from public.minimum_build), null, 'every build may run to begin with');
select is(
  (select emoji from public.quick_reactions),
  '["❤️", "💪", "😂", "🤤", "😮", "😡"]'::jsonb,
  'the bar starts as the app shipped it'
);
select throws_ok($$delete from public.minimum_build$$, '42501', null, 'the minimum build keeps its row');
select throws_ok($$delete from public.quick_reactions$$, '42501', null, 'the quick reactions keep their row');
select throws_ok($$update public.minimum_build set build = 'v190'$$, '23514', null, 'a build is numbers and dots');
select lives_ok($$update public.minimum_build set build = '190.1'$$, 'a build number such as 190.1 is taken');
select throws_ok($$update public.quick_reactions set emoji = '[]'$$, '23514', null, 'the bar always has an emoji');
select throws_ok(
  $$update public.quick_reactions set emoji = '["1", "2", "3", "4", "5", "6", "7"]'$$,
  '23514', null, 'the bar has at most six'
);
select throws_ok($$update public.minimum_build_events set minimum = '{"version": 2}'$$, '42501', null, 'the build log refuses an update');
select throws_ok($$truncate public.quick_reaction_events$$, '42501', null, 'the reactions log refuses a truncate');

select * from finish();
rollback;
