-- A member may wear a dedicated badge the team gave them (点子王, 捉虫队) on their player card
-- and beside their name instead of a weekly title: one or the other, never both. Whether they
-- hold it is the API's to check. Logged with the rest of the profile, so replaying
-- profile_events rebuilds it too.
alter table public.profiles
  add column equipped_team_badge text references public.badges (id),
  add constraint profiles_wears_one check (equipped_title is null or equipped_team_badge is null);

alter table public.profile_events
  add column equipped_team_badge text;
