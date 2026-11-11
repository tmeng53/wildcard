-- A team badge's line (Tracy, 2026-11-11: 点子王 had nothing under its name): what its card says
-- under the name, as a weekly title's 颁奖词 does, in each language. Optional; logged with the
-- badge's other changes in reward_catalog_events.
alter table public.badges
  add column lines jsonb check (
    lines is null or (
      coalesce(jsonb_typeof(lines -> 'version') = 'number', false)
      and coalesce(char_length(lines ->> 'zh-Hans') between 1 and 30, false)
      and coalesce(char_length(lines ->> 'zh-Hant') between 1 and 30, false)
      and coalesce(char_length(lines ->> 'en') between 1 and 60, false)
    )
  );
