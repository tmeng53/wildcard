-- The number on a member's player card in 我 (00 to 99), which they pick themselves; null until
-- they do, and the app then shows their place in their squad. Squadmates may share a number.
-- Logged with the rest of the profile, so replaying profile_events rebuilds it too.
alter table public.profiles
  add column jersey_number smallint check (jersey_number between 0 and 99);

alter table public.profile_events
  add column jersey_number smallint;
