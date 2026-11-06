-- 练了 is called 训练 everywhere in the app now (Tracy, 2026-11-06), so the 战报's winner words
-- that still say 练了 say 训练. Only a row that still has the old word changes, and the change is
-- logged with the whole new value like an admin's save (no one made it, so no changed_by).
with changed as (
  update public.week_summary_words
  set words = replace(words::text, '练了', '训练')::jsonb
  where words::text like '%练了%'
  returning words
)
insert into public.week_summary_word_events (changed_by, words)
select null, words from changed;
