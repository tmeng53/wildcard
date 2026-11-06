-- The words the model writes for the 战报's last page (这一周), over the squad's days trained
-- against its plans: {version, headline, line}. Saved with the awards, in the same statement
-- as given_at, and never changed after; null when the squad trained no day, or for awards
-- given before the model wrote them (the app then shows its own words).
alter table public.weekly_awards
  add column ending jsonb check (ending is null or (ending ->> 'version') = '1');
