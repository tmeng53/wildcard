-- The Sunday summary's (周日战报) words in Traditional Chinese, in Taiwan's words, so an app set to
-- 繁體中文 reads its awards and counts in it rather than in Simplified Chinese. Each award's name
-- and winner words and each count's name get a `zh-Hant`, written from its `zh-Hans` by the
-- table below (whatever an admin has changed it to by now); a phrase the table doesn't know keeps
-- its Simplified words until an admin writes it. Logged with the whole new value like an admin's
-- save (no one made it, so no changed_by).
with hant (hans, hant) as (
  values
    ('领奖台', '頒獎台'),
    ('练够计划', '練夠計畫'),
    ('皇冠', '皇冠'),
    ('本周最佳请假条', '本週最佳假單'),
    ('训练 {n} 天', '訓練 {n} 天'),
    ('练了 {n} 天', '練了 {n} 天'),
    ('{n} 个回应', '{n} 個回應'),
    ('训练天数', '訓練天數'),
    ('计划天数', '計畫天數'),
    ('打卡', '打卡'),
    ('请假条', '假單'),
    ('健康餐', '健康餐'),
    ('放纵餐', '欺騙餐'),
    ('收到的回应', '收到的回應')
),
current as (
  select words from public.week_summary_words where not (words::text like '%zh-Hant%')
),
-- Each award with its name and winner words in Traditional Chinese too.
awards as (
  select jsonb_object_agg(
    award.key,
    award.value
      || jsonb_build_object(
        'title',
        (award.value -> 'title')
          || jsonb_build_object(
            'zh-Hant',
            coalesce(
              (select hant from hant where hans = award.value #>> '{title,zh-Hans}'),
              award.value #>> '{title,zh-Hans}'
            )
          ),
        'winner',
        (award.value -> 'winner')
          || jsonb_build_object(
            'zh-Hant',
            jsonb_build_object(
              'one',
              coalesce(
                (select hant from hant where hans = award.value #>> '{winner,zh-Hans,one}'),
                award.value #>> '{winner,zh-Hans,one}'
              ),
              'other',
              coalesce(
                (select hant from hant where hans = award.value #>> '{winner,zh-Hans,other}'),
                award.value #>> '{winner,zh-Hans,other}'
              )
            )
          )
      )
  ) as awards
  from current, jsonb_each(current.words -> 'awards') as award
),
stats as (
  select jsonb_object_agg(
    stat.key,
    stat.value
      || jsonb_build_object(
        'zh-Hant',
        coalesce((select hant from hant where hans = stat.value ->> 'zh-Hans'), stat.value ->> 'zh-Hans')
      )
  ) as stats
  from current, jsonb_each(current.words -> 'stats') as stat
),
changed as (
  update public.week_summary_words
  set words = words || jsonb_build_object('awards', awards.awards, 'stats', stats.stats)
  from awards, stats
  where not (words::text like '%zh-Hant%')
  returning words
)
insert into public.week_summary_word_events (changed_by, words)
select null, words from changed;
