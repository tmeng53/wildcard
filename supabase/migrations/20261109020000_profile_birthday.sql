-- The member's birthday, which they choose to give at sign-up or in 设置 and may change or
-- remove there: a whole date, null until they give one or after they remove it. The heart rate
-- chart's zones use the age; the coach only ever reads the month and day. Logged with the rest of
-- the profile, so replaying profile_events rebuilds it too; deleting the account takes both.
alter table public.profiles
  add column birthday date check (birthday >= date '1900-01-01');

alter table public.profile_events
  add column birthday date;
