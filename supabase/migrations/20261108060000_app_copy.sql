-- The app's copy put over its String Catalog's, by key: an admin changes a line the app shows
-- (a button, a title, a push) without an app release. One row, owned by the app copy module,
-- changed only through the admin tools; the public catalog serves it, and phones use it from
-- their next launch. A key nothing was put for keeps the build's own words.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the other settings are (settings_log_append_only()).
create table public.app_copy (
  only_row boolean primary key default true check (only_row),
  -- Each line by its catalog key: {"<key>": {"zhHans": ..., "en": ..., "zhHant": ...}}, any
  -- language left out keeping the build's words.
  entries jsonb not null default '{}'::jsonb check (jsonb_typeof(entries) = 'object')
);

create table public.app_copy_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "entries": {...}}.
  copy jsonb not null check (coalesce(jsonb_typeof(copy -> 'version') = 'number', false))
);

create trigger app_copy_events_append_only
  before update or delete on public.app_copy_events
  for each row execute function public.settings_log_append_only();

create trigger app_copy_events_no_truncate
  before truncate on public.app_copy_events
  for each statement execute function public.settings_log_append_only();

create trigger app_copy_kept
  before delete on public.app_copy
  for each row execute function public.settings_row_kept();

create trigger app_copy_no_truncate
  before truncate on public.app_copy
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.app_copy enable row level security;
alter table public.app_copy_events enable row level security;

-- Nothing put to begin with: every phone shows its build's words.
with first as (
  insert into public.app_copy default values returning *
)
insert into public.app_copy_events (copy)
select jsonb_build_object('version', 1, 'entries', entries) from first;
