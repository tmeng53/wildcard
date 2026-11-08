-- Where each member roughly is, so the coach knows their local weather, and the day's weather
-- for each place, fetched once a day a place.
-- As with every table, only our API reads and writes these.

-- Member places -----------------------------------------------------------------------------

-- The member's approximate place, from the phone's approximate location (iOS's reduced
-- accuracy), rounded again to a 0.1° cell (about 11 km), only to look up the weather there.
-- One row a member: the latest place only, replaced when they move and deleted when they turn
-- location off. Unlike the app's other data this keeps no log, on purpose: a history of where
-- someone has been is more than the weather needs. Deleting the account takes it.
create table public.member_places (
  member_id uuid primary key references auth.users (id) on delete cascade,
  latitude numeric(3, 1) not null check (latitude between -90 and 90),
  longitude numeric(4, 1) not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);

-- Weather -----------------------------------------------------------------------------------

-- One day's forecast for one 0.1° cell, as the weather provider gave it (the shape is the
-- API's to read: condition, high and low in °C, chance of rain or snow). Fetched the first
-- time a coach needs it that day (again only if kept in a shape the API can't read); days
-- older than a week are removed.
create table public.weather_days (
  latitude numeric(3, 1) not null,
  longitude numeric(4, 1) not null,
  day date not null,
  weather jsonb not null,
  fetched_at timestamptz not null default now(),
  primary key (latitude, longitude, day)
);

create index weather_days_day_idx on public.weather_days (day);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.member_places enable row level security;
alter table public.weather_days enable row level security;
