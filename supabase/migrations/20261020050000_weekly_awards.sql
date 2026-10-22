-- Each squad's weekly awards (本周颁奖): the titles, award lines and moves an AI writes for
-- every member who checked in, from the week as it stood on Sunday at 8pm Eastern, and each
-- member's most-reacted check-in. Read by the Sunday 战报 story and the weekly poster's
-- stickers. Every rule (who gets what, the checks the AI's words pass, when the winners and
-- the admins are told) lives in the API's weekly-awards module; the database keeps keys and
-- shapes only.

-- One row per squad and week once anything happened to its awards: how the tries went until
-- one passes, then when they were given.
create table public.weekly_awards (
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- The week's Monday.
  week_start date not null check (extract(isodow from week_start) = 1),
  -- When a try passed and the winners below were saved; null until then, never changed after.
  given_at timestamptz,
  -- Tries that failed, and why the last one did: the provider's error name and status, never
  -- members' words.
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  last_error text,
  -- How many tries had failed when a member last nudged the organisers, so admins are told
  -- once per failed try however many members nudge.
  nudged_failures integer check (nudged_failures >= 0),
  created_at timestamptz not null default now(),
  -- When the winners were told, so each is told once however often the job runs.
  notified_at timestamptz,
  primary key (squad_id, week_start)
);

-- Each member's awards for a squad's week. A deleted account takes its rows with it.
create table public.weekly_award_winners (
  squad_id uuid not null,
  week_start date not null,
  member_id uuid not null references auth.users (id) on delete cascade,
  -- Their place in the squad's order (the order they joined).
  position integer not null check (position >= 0),
  -- The titles and the most-reacted check-in as stored JSON with its shape's version at the
  -- top: {"version": 1, ...}. The API owns the shape and parses it on every read.
  award jsonb not null check (coalesce(jsonb_typeof(award -> 'version') = 'number', false)),
  primary key (squad_id, week_start, member_id),
  foreign key (squad_id, week_start)
    references public.weekly_awards (squad_id, week_start) on delete cascade
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.weekly_awards enable row level security;
alter table public.weekly_award_winners enable row level security;
