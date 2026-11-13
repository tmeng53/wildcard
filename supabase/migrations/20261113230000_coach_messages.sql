-- 教练消息卡 (Tracy, 2026-11-12): cards admins put on members' coach pages, said by the squad's
-- coach with no model writing them. One template; what fills it (its line, picture, stars, box
-- to type in and buttons, and what each button does, step by step) is data, so a new question or
-- a new place to send someone needs no release. Nothing is ever sent on its own: a message goes
-- out only while an admin has one running (`put_coach_message`).
--
-- Changed only through admin tools. A message is never changed in place: each save is a new row
-- with its whole value, and the newest row for an id is what it says now, so the table is its own
-- log (public.settings_log_append_only).
create table public.coach_messages (
  id bigint generated always as identity primary key,
  message_id text not null check (message_id ~ '^[a-z0-9][a-z0-9-]{0,47}$'),
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  -- {"version": 1, "card": {...}, "members"?: [...], "startsAt": ..., "endsAt"?: ...}, as the API
  -- checks it.
  message jsonb not null check (coalesce(jsonb_typeof(message -> 'version') = 'number', false))
);

create index coach_messages_by_id on public.coach_messages (message_id, id desc);

create trigger coach_messages_append_only
  before update or delete on public.coach_messages
  for each row execute function public.settings_log_append_only();

create trigger coach_messages_no_truncate
  before truncate on public.coach_messages
  for each statement execute function public.settings_log_append_only();

alter table public.coach_messages enable row level security;

-- When a member first got a message, in which squad and from which coach: the card's time and
-- speaker from then on, so a later change of coach doesn't change who said it. Given once a
-- member, on their first read of the coach page while it runs and their squad has a coach.
create table public.coach_message_deliveries (
  member_id uuid not null references auth.users (id) on delete cascade,
  message_id text not null check (message_id ~ '^[a-z0-9][a-z0-9-]{0,47}$'),
  -- The squad it came in, so it shows only there; no key, so the row stays the member's log.
  squad_id uuid not null,
  coach_id text not null check (char_length(coach_id) between 1 and 48),
  at timestamptz not null default now(),
  primary key (member_id, message_id)
);

create index coach_message_deliveries_by_member
  on public.coach_message_deliveries (member_id, squad_id, at);

-- What a member did on each card of a message (the first card's path is '', a follow-up's the
-- buttons tapped to reach it): the button they tapped (`tap`), the stars they gave (`stars`) or
-- the words they typed (`text`), each once a card; the first stands.
create table public.coach_message_answers (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users (id) on delete cascade,
  message_id text not null check (message_id ~ '^[a-z0-9][a-z0-9-]{0,47}$'),
  path text not null check (path ~ '^(|[a-z0-9][a-z0-9-]{0,23}(\.[a-z0-9][a-z0-9-]{0,23})?)$'),
  part text not null check (part in ('tap', 'stars', 'text')),
  button text check (button ~ '^[a-z0-9][a-z0-9-]{0,23}$'),
  stars smallint check (stars between 1 and 5),
  text text check (char_length(text) between 1 and 500),
  at timestamptz not null default now(),
  check (
    (part = 'tap' and button is not null and stars is null and text is null)
    or (part = 'stars' and stars is not null and button is null and text is null)
    or (part = 'text' and text is not null and button is null and stars is null)
  ),
  unique (member_id, message_id, path, part)
);

create index coach_message_answers_by_message on public.coach_message_answers (message_id, at);

-- Both are a member's own logs: never changed, gone only with the account.
create trigger coach_message_deliveries_append_only
  before update or delete on public.coach_message_deliveries
  for each row execute function public.member_log_append_only();

create trigger coach_message_deliveries_no_truncate
  before truncate on public.coach_message_deliveries
  for each statement execute function public.member_log_append_only();

create trigger coach_message_answers_append_only
  before update or delete on public.coach_message_answers
  for each row execute function public.member_log_append_only();

create trigger coach_message_answers_no_truncate
  before truncate on public.coach_message_answers
  for each statement execute function public.member_log_append_only();

alter table public.coach_message_deliveries enable row level security;
alter table public.coach_message_answers enable row level security;

-- A message's card is marked seen like the coach's own.
alter table public.coach_card_seen drop constraint coach_card_seen_kind_check;
alter table public.coach_card_seen add constraint coach_card_seen_kind_check check (
  kind in ('board', 'note', 'challenge', 'challengeDone', 'gift', 'reply', 'answer', 'message')
);
