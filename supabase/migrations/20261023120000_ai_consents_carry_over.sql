-- The consent copy moved to version 2 (one short line under the squad button instead of the
-- long ticked sentence). Both say the member's words go to third-party AI, and the privacy
-- policy behind them didn't change, so the beta accounts that agreed to version 1 keep their
-- consent (Tracy, 2026-10-23): each gets a version 2 row with the time they first agreed.

insert into public.ai_consents (member_id, copy_version, given_at)
select member_id, 2, given_at
from public.ai_consents
where copy_version = 1
on conflict (member_id, copy_version) do nothing;
