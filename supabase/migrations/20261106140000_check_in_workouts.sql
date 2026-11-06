-- A 训练 imported from Apple Health (Tracy, 2026-11-06): the workout behind a post, one at most,
-- with only the numbers the member posted. Only the posted workout is uploaded, never a sync of
-- Health. The provider is open text, so Fitbit or Garmin later are new values, not a new table.
--
-- Deleting the post or the account removes it (deletion removes data). It is part of the
-- post's `check_in_events` value, so it is logged with every save. Heart rate lives only here:
-- the coach, the weekly awards and the drafts never read this table.
create table public.check_in_workouts (
  check_in_id uuid primary key references public.check_ins (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- `apple_health`; later `fitbit`, `garmin`.
  provider text not null check (provider ~ '^[a-z][a-z_]{1,30}$'),
  -- The provider's own id for the workout (an HKWorkout's UUID).
  provider_workout_id text not null check (char_length(provider_workout_id) between 1 and 100),
  started_at timestamptz not null,
  ended_at timestamptz not null check (ended_at >= started_at),
  -- {"version": 1, "durationSec"?, "distanceM"?, "paceSecPerKm"?, "speedKmh"?, "avgHr"?,
  --  "maxHr"?, "effort"?, "laps"?, "poolLengthM"?}: only the cells that were posted.
  summary jsonb not null check (coalesce(jsonb_typeof(summary -> 'version') = 'number', false)),
  -- {"version": 1, "hr"?: [{"t", "bpm"}], "laps"?: [seconds]}, kept only with the chart tile.
  series jsonb check (series is null or coalesce(jsonb_typeof(series -> 'version') = 'number', false)),
  -- {"version": 1, "points": [{"lat", "lon"}]}, trimmed 200 m at each end on the phone, kept
  -- only with the map tile.
  route jsonb check (route is null or coalesce(jsonb_typeof(route -> 'version') = 'number', false)),
  -- The map or chart tile's place among the post's photos: 1 is the cover. Null when the member
  -- took the tile off, and then neither a route nor a series is kept.
  tile_position smallint check (tile_position between 1 and 4),
  check ((tile_position is null) = (series is null and route is null)),
  -- A workout is posted once: the 「已发」 chip and the home card read it.
  constraint check_in_workouts_once unique (member_id, provider, provider_workout_id)
);

-- No grants (the default privileges in the first migration see to that) and no policies: like
-- the photos, only the API reads and writes it, each member's own through their check-ins.
alter table public.check_in_workouts enable row level security;
