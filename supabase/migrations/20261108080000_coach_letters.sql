-- The letter a coach leaves the next one when its squad changes coach (换教练, Tracy 2026-11-08):
-- written once, by the outgoing coach from the squad's memory files, for the squad's members to
-- read. The new coach never reads it; it keeps reading the same files. A plain firing writes none.

-- Each change of coach the outgoing coach was asked to write for, by the hire that made it: once,
-- so a retry or a second tap never pays for a second letter.
create table public.coach_letter_tries (
  hire_event_id bigint primary key references public.squad_coach_events (id) on delete cascade,
  squad_id uuid not null references public.squads (id) on delete cascade,
  at timestamptz not null default now()
);

-- The letters written: at most one a change of coach.
create table public.coach_letters (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  hire_event_id bigint not null unique
    references public.coach_letter_tries (hire_event_id) on delete cascade,
  from_coach text not null references public.coaches (id),
  to_coach text not null references public.coaches (id),
  check (from_coach <> to_coach),
  -- The squad's day it was written on, on the squad's clock, which the letter is dated.
  day date not null,
  text text not null check (char_length(text) between 1 and 200),
  at timestamptz not null default now()
);

create index coach_letters_by_squad on public.coach_letters (squad_id, id desc);

-- Logs like the coach's others: never changed or removed, except by the cascade of a squad's end.
create trigger coach_letter_tries_append_only
  before update or delete on public.coach_letter_tries
  for each row execute function public.coach_log_append_only();
create trigger coach_letter_tries_no_truncate
  before truncate on public.coach_letter_tries
  for each statement execute function public.settings_log_append_only();
create trigger coach_letters_append_only
  before update or delete on public.coach_letters
  for each row execute function public.coach_log_append_only();
create trigger coach_letters_no_truncate
  before truncate on public.coach_letters
  for each statement execute function public.settings_log_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_letter_tries enable row level security;
alter table public.coach_letters enable row level security;
