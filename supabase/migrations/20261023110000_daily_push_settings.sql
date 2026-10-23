-- The daily progress push for everyone, kept in the database so it changes without a deploy:
-- whether it goes out at all, and the hour on each member's own clock it goes out at. One row,
-- owned by the push module, changed only through the admin tools; the push job reads it on every
-- run. Each member's own switch (push_settings) still applies on top.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the other settings are (settings_log_append_only()).
create table public.daily_push_settings (
  only_row boolean primary key default true check (only_row),
  sending boolean not null,
  hour integer not null check (hour between 0 and 23)
);

create table public.daily_push_setting_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "sending": ..., "hour": ...}.
  settings jsonb not null check (coalesce(jsonb_typeof(settings -> 'version') = 'number', false))
);

create trigger daily_push_setting_events_append_only
  before update or delete on public.daily_push_setting_events
  for each row execute function public.settings_log_append_only();

create trigger daily_push_setting_events_no_truncate
  before truncate on public.daily_push_setting_events
  for each statement execute function public.settings_log_append_only();

create trigger daily_push_settings_kept
  before delete on public.daily_push_settings
  for each row execute function public.settings_row_kept();

create trigger daily_push_settings_no_truncate
  before truncate on public.daily_push_settings
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.daily_push_settings enable row level security;
alter table public.daily_push_setting_events enable row level security;

-- The first values: on, at 6pm, as the code had it.
with first as (
  insert into public.daily_push_settings (sending, hour) values (true, 18)
  returning *
)
insert into public.daily_push_setting_events (settings)
select jsonb_build_object('version', 1, 'sending', sending, 'hour', hour) from first;
