-- Two things the app reads from the public catalog, so they change after launch with no app
-- release: the lowest build that may still be used (older ones show only 有新版本 and a button to
-- the App Store), owned by the switches module, and the reaction bar's quick emoji, owned by the
-- check-ins module, which keeps reactions. One row each, changed only through the admin tools.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the other settings are (settings_log_append_only()).

create table public.minimum_build (
  only_row boolean primary key default true check (only_row),
  -- The lowest CFBundleVersion that may run (`190`, `190.1`), compared number by number; null
  -- lets every build run.
  build text check (build ~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$')
);

create table public.minimum_build_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "build": "190" | null}.
  minimum jsonb not null check (coalesce(jsonb_typeof(minimum -> 'version') = 'number', false))
);

create table public.quick_reactions (
  only_row boolean primary key default true check (only_row),
  -- The reaction bar's emoji, in order: ["❤️", ...]. Any one emoji is still a reaction.
  emoji jsonb not null check (
    jsonb_typeof(emoji) = 'array' and jsonb_array_length(emoji) between 1 and 6
  )
);

create table public.quick_reaction_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- The whole new value, as the API stores it: {"version": 1, "emoji": [...]}.
  reactions jsonb not null check (coalesce(jsonb_typeof(reactions -> 'version') = 'number', false))
);

create trigger minimum_build_events_append_only
  before update or delete on public.minimum_build_events
  for each row execute function public.settings_log_append_only();

create trigger minimum_build_events_no_truncate
  before truncate on public.minimum_build_events
  for each statement execute function public.settings_log_append_only();

create trigger minimum_build_kept
  before delete on public.minimum_build
  for each row execute function public.settings_row_kept();

create trigger minimum_build_no_truncate
  before truncate on public.minimum_build
  for each statement execute function public.settings_row_kept();

create trigger quick_reaction_events_append_only
  before update or delete on public.quick_reaction_events
  for each row execute function public.settings_log_append_only();

create trigger quick_reaction_events_no_truncate
  before truncate on public.quick_reaction_events
  for each statement execute function public.settings_log_append_only();

create trigger quick_reactions_kept
  before delete on public.quick_reactions
  for each row execute function public.settings_row_kept();

create trigger quick_reactions_no_truncate
  before truncate on public.quick_reactions
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.minimum_build enable row level security;
alter table public.minimum_build_events enable row level security;
alter table public.quick_reactions enable row level security;
alter table public.quick_reaction_events enable row level security;

-- Every build may run to begin with.
with first as (
  insert into public.minimum_build (build) values (null) returning *
)
insert into public.minimum_build_events (minimum)
select jsonb_build_object('version', 1, 'build', build) from first;

-- The bar the app shipped with.
with first as (
  insert into public.quick_reactions (emoji) values ('["❤️", "💪", "😂", "🤤", "😮", "😡"]'::jsonb)
  returning *
)
insert into public.quick_reaction_events (reactions)
select jsonb_build_object('version', 1, 'emoji', emoji) from first;
