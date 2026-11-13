-- How members rate the places they train at (Tracy, 2026-11-12): one score from 1 to 5 a member
-- and place, which they may change; the latest stands. Squadmates see the average over their
-- squad's members. Meals are rated on the meal check-in itself, not here.
-- As with every table, only our API reads and writes it.

-- Every score given, never changed: the table is its own log, until the account's deletion
-- takes the member's rows.
create table public.place_ratings (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- `apple:` and Apple Maps' identifier for the place, as the post's place carries it.
  place_key text not null check (place_key ~ '^apple:[A-Za-z0-9._-]{1,200}$'),
  stars smallint not null check (stars between 1 and 5),
  at timestamptz not null
);

create index place_ratings_place_member_at_idx
  on public.place_ratings (place_key, member_id, at desc, id desc);

create trigger place_ratings_append_only
  before update or delete on public.place_ratings
  for each row execute function public.member_log_append_only();

create trigger place_ratings_no_truncate
  before truncate on public.place_ratings
  for each statement execute function public.member_log_append_only();

alter table public.place_ratings enable row level security;
