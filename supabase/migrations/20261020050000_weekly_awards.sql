-- Each squad's weekly awards (本周颁奖): the titles, award lines and moves an AI writes for
-- every member who checked in, from the week as it stood on Sunday at 8pm Eastern, and each
-- member's most-reacted check-in. Written once per squad and week, read by the Sunday 战报
-- story and the weekly poster's stickers. Every rule (who gets what, the checks the AI's
-- words pass, when the winners are told) lives in the API's weekly-awards module; the
-- database keeps keys and shapes only.

create table public.weekly_awards (
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- The week's Monday.
  week_start date not null check (extract(isodow from week_start) = 1),
  -- The awards as stored JSON with its shape's version at the top: {"version": 1, ...}. The API
  -- owns the shape and parses it on every read.
  awards jsonb not null check (coalesce(jsonb_typeof(awards -> 'version') = 'number', false)),
  created_at timestamptz not null default now(),
  -- When the winners were told, so each is told once however often the job runs.
  notified_at timestamptz,
  primary key (squad_id, week_start)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.weekly_awards enable row level security;
