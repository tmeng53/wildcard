-- Each coach's words in 繁體中文 and English (Tracy, 2026-11-08: new coaches launch as data, in
-- every language the app speaks): its name, 头衔, 口头禅 and 简历 as the app shows them, by language,
-- {"zh-Hant": {...}, "en": {...}}. A language left out shows the Chinese ones. Put with put_coach
-- and logged with the whole coach in coach_catalog_events, as every other field.
alter table public.coaches
  add column translations jsonb not null default '{}'::jsonb
    check (jsonb_typeof(translations) = 'object');
