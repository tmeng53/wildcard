-- Each coach's 简历, as the app's 教练市场 shows it (Tracy approved the hire page design,
-- 2026-11-01): a title next to the name, its fictional 履历, years coaching and a word on them,
-- tags for its card, and its 期望待遇. These replace the one-line 资历卡 (`credentials`).
-- The model never reads any of them: the 简历 is for the app, the soul is for the model.

alter table public.coaches
  add column title text,
  add column background text,
  add column years_coaching integer,
  add column experience text,
  add column tags text[],
  add column pay text;

-- 毛头, the first coach, as approved on the design.
update public.coaches set
  title = '混混教练',
  background = '体育学院刚毕业，该学的都学了，就是证还没考下来',
  years_coaching = 0,
  experience = '热情满格',
  tags = array['体院应届', '懂行', '松弛', '风趣'],
  pay = '管饭就行'
where id = 'xiaohun';

-- Any other coach keeps its old card as its 履历 until an admin writes its 简历.
update public.coaches set
  title = '教练',
  background = left(credentials, 100),
  years_coaching = 0,
  experience = '热情满格',
  tags = array[left(style, 6)],
  pay = '管饭就行'
where title is null;

alter table public.coaches
  alter column title set not null,
  alter column background set not null,
  alter column years_coaching set not null,
  alter column experience set not null,
  alter column tags set not null,
  alter column pay set not null,
  add constraint coaches_title check (char_length(title) between 1 and 10),
  add constraint coaches_background check (char_length(background) between 1 and 100),
  add constraint coaches_years_coaching check (years_coaching between 0 and 60),
  add constraint coaches_experience check (char_length(experience) between 1 and 20),
  add constraint coaches_tags check (
    cardinality(tags) between 1 and 5 and array_position(tags, null) is null
  ),
  add constraint coaches_pay check (char_length(pay) between 1 and 20),
  drop column credentials;

-- The change, logged with each coach's whole new value, as the API stores it.
insert into public.coach_catalog_events (changed_by, coach_id, coach)
select null, id, jsonb_build_object(
  'version', 2,
  'id', id,
  'tier', tier,
  'name', name,
  'title', title,
  'catchphrase', catchphrase,
  'background', background,
  'yearsCoaching', years_coaching,
  'experience', experience,
  'tags', to_jsonb(tags),
  'pay', pay,
  'style', style,
  'soul', soul,
  'look', look,
  'offered', offered
)
from public.coaches;
