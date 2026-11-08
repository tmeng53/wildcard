-- The coach page (Tracy, 2026-11-08): everything a squad's coach said to a member comes as a
-- stack of cards, one per thing (its 战术板 line, the member's morning note, the day's
-- challenge, a gift, its reply to their check-in, its answer to their reply). A card swiped
-- away is seen and goes to 以前.

-- The challenge's own small line under its title: the coach talking to the member about why
-- (「昨天跑完腿还紧，睡前拉一拉。」), up to 24 characters; notes from before have none.
alter table public.coach_member_notes
  add column challenge_line text check (char_length(challenge_line) between 1 and 24),
  add constraint coach_member_notes_challenge_line check (
    challenge_line is null or challenge_title is not null
  );

-- Which of the coach's cards a member has seen, by the card's kind and its id in that kind's
-- own table (a 战术板 line's day, a note's id, a gift's piece, a reply's or answer's id). Once
-- a card; never changed, and gone with the member or the squad.
create table public.coach_card_seen (
  member_id uuid not null references auth.users (id) on delete cascade,
  squad_id uuid not null references public.squads (id) on delete cascade,
  kind text not null check (
    kind in ('board', 'note', 'challenge', 'challengeDone', 'gift', 'reply', 'answer')
  ),
  card_id text not null check (char_length(card_id) between 1 and 64),
  at timestamptz not null default now(),
  primary key (member_id, squad_id, kind, card_id)
);

alter table public.coach_card_seen enable row level security;

create function public.coach_card_seen_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or not exists (select 1 from public.squads where id = old.squad_id)
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger coach_card_seen_append_only
  before update or delete on public.coach_card_seen
  for each row execute function public.coach_card_seen_append_only();
create trigger coach_card_seen_no_truncate
  before truncate on public.coach_card_seen
  for each statement execute function public.settings_log_append_only();

-- The day's challenge (今日挑战) as its own thing: given on the morning note, accepted or let
-- go, and done. Either the member says they did it (我完成了) or the coach, seeing it in that
-- day's check-ins, marks it done (its own card, `challengeDone`); only on the challenge's own
-- day, and the first one stands. Once a note; it goes only with its note.
create table public.coach_challenge_completions (
  note_id bigint primary key references public.coach_member_notes (id) on delete cascade,
  by text not null check (by in ('member', 'coach')),
  at timestamptz not null default now()
);

create trigger coach_challenge_completions_append_only
  before update or delete on public.coach_challenge_completions
  for each row execute function public.coach_note_marks_append_only();
create trigger coach_challenge_completions_no_truncate
  before truncate on public.coach_challenge_completions
  for each statement execute function public.settings_log_append_only();

alter table public.coach_challenge_completions enable row level security;

-- A let-go challenge can't be done. Answers and completions both take the note's row lock
-- first, so a 算了 and a 我完成了 (or the coach's mark) from two places at once run one after
-- the other, and a completion that comes after a 算了 is not kept.
create function public.coach_challenge_lock_note() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform 1 from public.coach_member_notes where id = new.note_id for no key update;
  if tg_table_name = 'coach_challenge_completions' and exists (
    select 1 from public.coach_challenge_answers
    where note_id = new.note_id and answer = 'declined'
  ) then
    return null;
  end if;
  return new;
end;
$$;

create trigger coach_challenge_completions_not_declined
  before insert on public.coach_challenge_completions
  for each row execute function public.coach_challenge_lock_note();
create trigger coach_challenge_answers_lock_note
  before insert on public.coach_challenge_answers
  for each row execute function public.coach_challenge_lock_note();

-- Why the member let a challenge go, if they said (「我鸡蛋过敏」): only with 算了, for the
-- coach to remember. Never shown to squadmates. Up to 60 characters, which the API counts as
-- people see them; this bound is the API's raw one (1000 UTF-16 units), so whatever it takes fits.
alter table public.coach_challenge_answers
  add column reason text check (char_length(reason) between 1 and 1000),
  add constraint coach_challenge_answers_reason check (reason is null or answer = 'declined');
