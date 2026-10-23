-- The 请假条 drafts' meme chance as double precision, the type the API reads and writes it as, so
-- the settings row and its log keep the same value. The beta had already run the first AI
-- settings migration with `real`, so this one changes it there; a `real` value is rounded back
-- to what was set (0.3, not 0.30000001192092896).
alter table public.disclaimer_draft_settings
  alter column meme_chance type double precision using round(meme_chance::numeric, 6)::double precision;
