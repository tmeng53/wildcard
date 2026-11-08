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
  kind text not null check (kind in ('board', 'note', 'challenge', 'gift', 'reply', 'answer')),
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
