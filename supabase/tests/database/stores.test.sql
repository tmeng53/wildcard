-- What the database keeps true about the stores and pieces however they are edited.
begin;
select plan(10);

select is(
  (select array_agg(id order by position) from public.stores),
  array['warmup', 'lap', 'nolook', 'moss', 'halfmoon', 'deuce', 'powder'],
  'the first stores are the seven the art has, in the street''s order'
);
select is(
  (select switch_id from public.stores where id = 'powder'),
  'winter',
  'POWDER DAY is open only while the winter switch is on'
);
select is(
  (select array_agg(id order by id) from public.pieces where store_id = 'powder' and starter),
  array['powder-helmet', 'powder-rice', 'powder-saba', 'powder-salmon'],
  'POWDER DAY''s four starters are the pieces with no rule'
);
select is(
  (select count(*)::int from public.pieces where switch_id is not null),
  0,
  'no piece has a switch of its own to begin with'
);
select hasnt_column('public', 'reward_triggers', 'switch_id', 'triggers say only how a piece is earned');
select throws_ok(
  $$delete from public.pieces where id = 'powder-tuna'$$,
  '42501', null, 'a piece is never deleted'
);
select throws_ok(
  $$update public.stores set id = 'snow' where id = 'powder'$$,
  '42501', null, 'a store keeps its id'
);
select throws_ok(
  $$truncate public.pieces cascade$$,
  '42501', null, 'a truncate cannot wipe the pieces, since it would skip the log'
);

update public.pieces set switch_id = 'winter' where id = 'powder-scarf';
update public.pieces set switch_id = 'winter' where id = 'powder-scarf';
select is(
  (select count(*)::int from public.piece_events where value ->> 'id' = 'powder-scarf'),
  2,
  'a change is logged once with its full value, a save that changed nothing not at all'
);
select throws_ok(
  $$delete from public.store_events$$,
  '42501', null, 'the store log is append-only'
);

select * from finish();
rollback;
