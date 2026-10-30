-- Moving a picker tab renumbers the tabs in one statement, which swaps places on the way; a
-- unique check after each row would refuse that, so it waits for the end of the statement, as
-- the sports' and short lists' places already do.
alter table public.sport_categories
  drop constraint sport_categories_position_key,
  add constraint sport_categories_position_key unique (position) deferrable initially immediate;
