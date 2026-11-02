-- What the database keeps true about the meme library however the API writes it.
begin;
select plan(6);

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

select * from finish();
rollback;
