-- The Sunday summary's words and their log: no code reads or writes them any more, and no admin
-- tool names them. A new migration drops them, since the hosted database already ran the one
-- that made them.
drop table public.week_summary_word_events;
drop table public.week_summary_words;
