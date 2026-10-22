-- What squadmates see of a member besides their check-ins. Every rule about these values
-- (lengths, ids, swatches) is the API's, like every other rule; the database keeps only
-- what keeps the rows whole.

-- The catchphrase (口头禅): what their character shouts when the squad cheers a teammate's
-- 练了. Null until they pick one, and the app then uses their persona's own line.
alter table public.profiles add column catchphrase text;

-- Their character, made together in the character editor right after signing in: the
-- nickname squadmates call them, and the look (persona, a variant per slot, swatches) as
-- JSON with a top-level numeric version. Both null until then, never one without the other.
alter table public.profiles
  add column nickname text,
  add column look jsonb,
  add constraint profiles_character_whole check ((nickname is null) = (look is null)),
  add constraint profiles_look_versioned check (
    look is null or coalesce(jsonb_typeof(look -> 'version') = 'number', false)
  );
