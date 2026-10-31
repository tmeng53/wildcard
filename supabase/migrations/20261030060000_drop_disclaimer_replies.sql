-- 请假条 gets no word replies in the first release (emoji reactions only; comments come later), so
-- the table the replies were kept in goes. It is dropped by a new migration, not by editing
-- 20261022120000_disclaimer_replies.sql, since the hosted database has already run that one.
drop table public.disclaimer_replies;
