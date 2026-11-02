-- What the database keeps true about the meme library however the API writes it.
begin;
select plan(12);

select lives_ok(
  $$insert into public.memes (phrase, payload, approved_at) values ('city不city', '{"version":1}', now())$$,
  'an approved meme is saved'
);
select throws_ok(
  $$insert into public.memes (phrase, payload, approved_at) values ('city不city', '{"version":1}', now())$$,
  '23505', 'duplicate key value violates unique constraint "memes_phrase_key"',
  'a meme is saved once, so approving it again can''t add a second copy'
);
select throws_ok(
  $$insert into public.memes (phrase, payload, approved_at) values ('松弛感', '{"meaning":"chill"}', now())$$,
  '23514', null, 'stored meme JSON carries its version'
);
select throws_ok(
  $$insert into public.memes (phrase, payload, approved_at) values ('松弛感', '{"version":"1"}', now())$$,
  '23514', null, 'the version is a number'
);
select throws_ok(
  $$insert into public.memes (phrase, payload, approved_at, expires_at) values ('班味', '{"version":1}', now(), now())$$,
  '23514', null, 'a meme expires after its approval, or it would never be used'
);
select lives_ok(
  $$insert into public.memes (phrase, payload, approved_at, expires_at) values ('班味', '{"version":1}', now(), now() + interval '7 days')$$,
  'a meme tied to a moment is saved with when it expires'
);

select is(
  (select array_agg(op order by id) from public.meme_events where value ->> 'phrase' in ('city不city', '班味')),
  array['INSERT', 'INSERT'], 'each approved meme is logged once'
);
update public.memes set expires_at = approved_at + interval '14 days' where phrase = '班味';
update public.memes set expires_at = expires_at where phrase = '班味';
select is(
  (select count(*)::int from public.meme_events where value ->> 'phrase' = '班味' and op = 'UPDATE'),
  1, 'moving an expiry is logged, and a save that changed nothing is not'
);
select is(
  (select value ->> 'expires_at' from public.meme_events where value ->> 'phrase' = '班味' order by id desc limit 1)::timestamptz,
  (select expires_at from public.memes where phrase = '班味'),
  'the log keeps the meme''s full new row'
);
update public.memes set disabled_at = now() where phrase = 'city不city';
select is(
  (select count(*)::int from public.meme_events where value ->> 'phrase' = 'city不city' and value ->> 'disabled_at' is not null),
  1, 'turning a meme off is logged'
);
select throws_ok($$update public.meme_events set value = '{}'$$, '42501', null, 'the meme log refuses an update');
select throws_ok($$delete from public.meme_events$$, '42501', null, 'the meme log refuses a delete');

select * from finish();
rollback;
