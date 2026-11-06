-- Animals pick a face as people do (Tracy, 2026-11-06). Their coats drew a blush of their own,
-- which the cheeks a look picks now draw instead, so every animal saved before this wears the
-- same blush as `rosy` cheeks and looks as it did. A person (`peach`) and a look that already
-- picks cheeks are left as they are. Logged like any profile change, so replaying
-- profile_events rebuilds the new look too.
with changed as (
  update public.profiles
  set look = jsonb_set(look, '{variants,cheeks}', '"rosy"')
  where look -> 'variants' ->> 'body' is not null
    and look -> 'variants' ->> 'body' <> 'peach'
    and not (look -> 'variants') ? 'cheeks'
  returning member_id, time_zone, catchphrase, nickname, look, jersey_number, equipped_title
)
insert into public.profile_events (member_id, time_zone, catchphrase, nickname, look, jersey_number, equipped_title)
select member_id, time_zone, catchphrase, nickname, look, jersey_number, equipped_title
from changed;
