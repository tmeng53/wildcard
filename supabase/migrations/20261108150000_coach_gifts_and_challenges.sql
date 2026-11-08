-- The coach gives gifts and sets challenges (Tracy, 2026-11-08).
--
-- Gifts: a coach (on its daily wake) or an admin, in the coach's name, gives a member a piece
-- from the pool with a line of its own. At most one gift a member a week, checked in code where
-- it is given and held by a unique index. A gift is a first-class record: its line, who gave it (the coach, or an admin as
-- the coach) and when the member opened it (拆开), kept apart because a gift row is never changed.
--
-- Challenges: the morning note (便条) may carry one small challenge for the day: a title, and an
-- optional amount with its unit. The member takes it (接受挑战) or lets it go (算了), once.

-- What the model reads about each piece in the pool, so it knows what it would be giving.
alter table public.gift_pieces
  add column description text check (char_length(description) between 1 and 200);

-- Older gifts (none were given before this) have no line and were given by the coach.
-- `week_from` is the start of the week it counts for (the squad's Monday at midnight, on its
-- clock): one gift a member a week holds here too, so two givers at once can't both give.
alter table public.coach_gifts
  add column line text check (char_length(line) between 1 and 60),
  add column given_by text not null default 'coach' check (given_by in ('coach', 'admin')),
  add column admin_id uuid references auth.users (id) on delete set null,
  add column week_from timestamptz;

create unique index coach_gifts_one_a_week on public.coach_gifts (member_id, week_from);
create index coach_gifts_admin_id_idx on public.coach_gifts (admin_id);

-- A gift is still never changed, but when the admin who gave it deletes their account, its
-- `admin_id` turns null and nothing else; deleting the member's account takes the gift.
create function public.coach_gifts_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from auth.users where id = old.member_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.admin_id is null
    and old.admin_id is not null
    and not exists (select 1 from auth.users where id = old.admin_id)
    and (new.member_id, new.piece_id, new.coach_id, new.squad_id, new.given_at, new.line,
      new.given_by, new.week_from)
      is not distinct from (old.member_id, old.piece_id, old.coach_id, old.squad_id,
      old.given_at, old.line, old.given_by, old.week_from)
  then
    return new;
  end if;
  raise exception 'coach_gifts is append-only' using errcode = '42501';
end;
$$;

drop trigger coach_gifts_append_only on public.coach_gifts;
create trigger coach_gifts_append_only
  before update or delete on public.coach_gifts
  for each row execute function public.coach_gifts_append_only();

-- When the member opened each gift (拆开), and whether they put it on then (立刻穿上) or kept it
-- for later (一会儿再说). Once a gift; it goes only with its gift.
create table public.coach_gift_opens (
  member_id uuid not null,
  piece_id text not null,
  worn boolean not null,
  at timestamptz not null default now(),
  primary key (member_id, piece_id),
  foreign key (member_id, piece_id) references public.coach_gifts (member_id, piece_id)
    on delete cascade
);

create trigger coach_gift_opens_append_only
  before update or delete on public.coach_gift_opens
  for each row execute function public.member_log_append_only();
create trigger coach_gift_opens_no_truncate
  before truncate on public.coach_gift_opens
  for each statement execute function public.member_log_append_only();

alter table public.coach_gift_opens enable row level security;

-- A morning note's challenge: a title of up to 8 characters, and an amount (a whole number) with
-- a unit of up to 4 characters, or neither.
alter table public.coach_member_notes
  add column challenge_title text check (char_length(challenge_title) between 1 and 8),
  add column challenge_amount integer check (challenge_amount between 1 and 9999),
  add column challenge_unit text check (char_length(challenge_unit) between 1 and 4),
  add constraint coach_member_notes_challenge_whole check (
    (challenge_amount is null) = (challenge_unit is null)
    and (challenge_title is not null or challenge_amount is null)
  );

-- What the member answered a note's challenge: taken or let go. Once a note; it goes only with
-- its note.
create table public.coach_challenge_answers (
  note_id bigint primary key references public.coach_member_notes (id) on delete cascade,
  answer text not null check (answer in ('accepted', 'declined')),
  at timestamptz not null default now()
);

create trigger coach_challenge_answers_append_only
  before update or delete on public.coach_challenge_answers
  for each row execute function public.coach_note_marks_append_only();
create trigger coach_challenge_answers_no_truncate
  before truncate on public.coach_challenge_answers
  for each statement execute function public.settings_log_append_only();

alter table public.coach_challenge_answers enable row level security;
