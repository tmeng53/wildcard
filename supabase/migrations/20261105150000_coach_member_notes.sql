-- The coach's morning note to each member (便条): one line a member a squad a day, written by
-- the squad's daily wake, read only by that member. Delivered at the settings' `note_hour` (8am
-- to begin with) on the member's clock: a silent push under the member's `coach` switch and a
-- notice in their bell, whatever the switch.

alter table public.coach_settings
  add column note_hour integer not null default 8 check (note_hour between 0 and 23);

create table public.coach_member_notes (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  coach_id text not null references public.coaches (id),
  day date not null,
  text text not null check (char_length(text) between 1 and 60),
  wake_id bigint references public.coach_wakes (id) on delete set null,
  at timestamptz not null default now(),
  unique (squad_id, member_id, day)
);

create index coach_member_notes_member on public.coach_member_notes (member_id, id desc);

-- When each note was delivered (pushed and told in the bell): once a note.
create table public.coach_member_note_deliveries (
  note_id bigint primary key references public.coach_member_notes (id) on delete cascade,
  at timestamptz not null default now()
);

create trigger coach_member_notes_append_only
  before update or delete on public.coach_member_notes
  for each row execute function public.coach_log_append_only();
create trigger coach_member_notes_no_truncate
  before truncate on public.coach_member_notes
  for each statement execute function public.settings_log_append_only();

alter table public.coach_member_notes enable row level security;
alter table public.coach_member_note_deliveries enable row level security;

-- When the member put each note away on 今天 (收下): once a note, so it shows once on any phone.
create table public.coach_member_note_reads (
  note_id bigint primary key references public.coach_member_notes (id) on delete cascade,
  at timestamptz not null default now()
);

alter table public.coach_member_note_reads enable row level security;

-- A note's delivery and its putting away are never changed: they go only with their note.
create or replace function public.coach_note_marks_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.coach_member_notes where id = old.note_id) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger coach_member_note_deliveries_append_only
  before update or delete on public.coach_member_note_deliveries
  for each row execute function public.coach_note_marks_append_only();
create trigger coach_member_note_deliveries_no_truncate
  before truncate on public.coach_member_note_deliveries
  for each statement execute function public.settings_log_append_only();
create trigger coach_member_note_reads_append_only
  before update or delete on public.coach_member_note_reads
  for each row execute function public.coach_note_marks_append_only();
create trigger coach_member_note_reads_no_truncate
  before truncate on public.coach_member_note_reads
  for each statement execute function public.settings_log_append_only();
