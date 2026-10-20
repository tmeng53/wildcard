-- Each squad's weekly awards (本周颁奖): the titles, award lines and moves an AI writes for
-- every member who checked in, from the week as it stood on Sunday at 8pm Eastern, and each
-- member's most-reacted check-in. One row per squad and week: written once the AI's answer
-- passes, and until then how the tries went (for the admin a member's nudge tells). Read by the
-- Sunday 战报 story and the weekly poster's stickers. Every rule (who gets what, the checks the AI's
-- words pass, when the winners are told) lives in the API's weekly-awards module; the
-- database keeps keys and shapes only.

create table public.weekly_awards (
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- The week's Monday.
  week_start date not null check (extract(isodow from week_start) = 1),
  -- The awards as stored JSON with its shape's version at the top: {"version": 1, ...}. The API
  -- owns the shape and parses it on every read. Null until a try passes; never rewritten after.
  awards jsonb check (awards is null or coalesce(jsonb_typeof(awards -> 'version') = 'number', false)),
  -- Tries that failed, and why the last one did (the provider's error, never members' words).
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  last_error text,
  -- When a member first nudged the organisers about awards that hadn't come, so an admin is
  -- told once a squad and week.
  nudged_at timestamptz,
  created_at timestamptz not null default now(),
  -- When the winners were told, so each is told once however often the job runs.
  notified_at timestamptz,
  primary key (squad_id, week_start)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.weekly_awards enable row level security;
