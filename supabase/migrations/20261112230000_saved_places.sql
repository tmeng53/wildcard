-- Places a member saved (收藏, Tracy 2026-11-12): from a place's page, with an optional note,
-- seen only by them.
--
-- The log is the table: one row per change, oldest first, with the whole new value. A place's
-- latest row stands: `saved` with its place and note, or `removed`. Replaying it gives what a
-- member had saved on any day. Only grows (public.member_log_append_only); deleting the account
-- takes it.
create table public.saved_place_events (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- Which place (`@wildcard/places`' PlaceKey): `apple:` and Apple Maps' id, or `squad:` and a
  -- squad place's id.
  place_key text not null check (
    place_key ~ '^(apple:[A-Za-z0-9._-]{1,200}|squad:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$'
  ),
  kind text not null check (kind in ('saved', 'removed')),
  -- For `saved`: the place as the app sent it, `{"version": 1, "place": {...}}`.
  place jsonb check (place is null or coalesce(jsonb_typeof(place -> 'version') = 'number', false)),
  note text,
  at timestamptz not null default now(),
  check ((kind = 'saved') = (place is not null)),
  check (kind = 'saved' or note is null)
);

create index saved_place_events_member_id_place_key_idx
  on public.saved_place_events (member_id, place_key, id);

create trigger saved_place_events_append_only
  before update or delete on public.saved_place_events
  for each row execute function public.member_log_append_only();

create trigger saved_place_events_no_truncate
  before truncate on public.saved_place_events
  for each statement execute function public.member_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.saved_place_events enable row level security;
