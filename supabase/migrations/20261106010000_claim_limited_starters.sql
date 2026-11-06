-- 领取 for a limited store's starters (Tracy, 2026-11-05): a starter of a store or piece that
-- follows a switch (POWDER DAY's four) waits in its store marked new, like an unlocked piece, and
-- a member who claims it keeps it once its switch turns off. So a claim is no longer only of an
-- unlocked piece: the API decides what may be claimed (anything the member's shelf holds as
-- theirs), and the table keeps only that it names a listed piece and goes with the account.
alter table public.piece_claims
  drop constraint piece_claims_member_id_kind_piece_id_fkey,
  add foreign key (member_id) references auth.users (id) on delete cascade,
  add foreign key (piece_id) references public.pieces (id);
