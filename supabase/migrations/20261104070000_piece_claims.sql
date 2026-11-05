-- 领取 (Tracy, 2026-11-04, the approved wardrobe design): a piece the member unlocked waits in its
-- store with NEW until they claim it there; then it is in their wardrobe (我的衣橱), on every phone.
-- Nothing is bought: claiming only puts an unlocked piece in the wardrobe.

-- What each member claimed: one row per piece, never changed or removed, so it is its own log. A
-- claim is of a piece the member unlocked (the foreign key), kept while their account is.
create table public.piece_claims (
  member_id uuid not null,
  -- Always a piece; here so the claim can name the unlock it is of.
  kind text not null default 'piece' check (kind = 'piece'),
  piece_id text not null,
  claimed_at timestamptz not null default now(),
  primary key (member_id, piece_id),
  foreign key (member_id, kind, piece_id)
    references public.member_unlocks (member_id, kind, item_id) on delete cascade
);

create trigger piece_claims_append_only
  before update or delete on public.piece_claims
  for each row execute function public.member_log_append_only();
create trigger piece_claims_no_truncate
  before truncate on public.piece_claims
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.piece_claims enable row level security;
