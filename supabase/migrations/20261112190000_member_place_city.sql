-- The city the member's phone says it is in, with their place, so the coach can name where they
-- are (「多伦多今天下雨」) instead of guessing from the time zone. The phone looks it up from its
-- approximate location (Apple's reverse geocoding, in the app's language) and sends it with the
-- cell; a phone that can't tell sends none. Like the place, only the latest is kept, with no
-- log, and it goes when the place goes.
alter table public.member_places
  add column city text check (city is null or char_length(city) between 1 and 60);
