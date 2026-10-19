-- A member's catchphrase (口头禅): what their character shouts when the squad cheers a
-- teammate's 练了. Null until they pick one, and the app then uses their persona's own line.
-- Its rules (1 to 10 characters, one line, no links) are the API's, like every other rule.
alter table public.profiles add column catchphrase text;
