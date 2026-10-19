-- Every squad has an invite code its members share: a friend types it, or an invite link
-- carries it, to join. The API makes the code and keeps every rule about joining (at most
-- 8 members, at most 3 squads a member); the database keeps codes unique, so two squads
-- can never answer to one code.
--
-- No squad exists yet anywhere (Wildcard has no users), so the column needs no default.

alter table public.squads add column invite_code text not null;

alter table public.squads add constraint squads_invite_code_key unique (invite_code);
