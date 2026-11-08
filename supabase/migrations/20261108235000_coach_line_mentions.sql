-- Whom a coach's line @s (Tracy, 2026-11-08): its reply to a check-in or its answer to a reply,
-- so the app can show each 「@昵称」 in bold and open that member's card. In the order written,
-- at most 3 (the coach's `at`). Written with the line and never changed, so each table is its
-- own log; the line's removal (its squad's end, its check-in's deletion) or a mentioned
-- account's deletion removes the row.
create table public.coach_reply_mentions (
  reply_id bigint not null references public.coach_replies (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  position smallint not null check (position between 0 and 2),
  primary key (reply_id, member_id),
  unique (reply_id, position)
);

create index coach_reply_mentions_member_id_idx on public.coach_reply_mentions (member_id);

create table public.coach_answer_mentions (
  answer_id bigint not null references public.coach_answers (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  position smallint not null check (position between 0 and 2),
  primary key (answer_id, member_id),
  unique (answer_id, position)
);

create index coach_answer_mentions_member_id_idx on public.coach_answer_mentions (member_id);

-- Never changed, as a comment's mentions.
create trigger coach_reply_mentions_unchanged
  before update on public.coach_reply_mentions
  for each row execute function public.check_in_comment_mentions_unchanged();

create trigger coach_answer_mentions_unchanged
  before update on public.coach_answer_mentions
  for each row execute function public.check_in_comment_mentions_unchanged();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.coach_reply_mentions enable row level security;
alter table public.coach_answer_mentions enable row level security;
