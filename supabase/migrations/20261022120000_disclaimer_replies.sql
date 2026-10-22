-- Teammates' replies to a 今日请假条 (准了 and the like), apart from reactions: a member may
-- leave both on one 请假条. As with reactions, at most one reply per member per 请假条, and
-- replying again replaces it. Which replies exist is the API's to decide, so `kind` is text it
-- checks, not an enum a migration would have to change. So is the rule that only a 请假条 takes
-- replies: the database keeps only what must stay true however rows are written.
create table public.disclaimer_replies (
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  replied_at timestamptz not null,
  primary key (check_in_id, member_id)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.disclaimer_replies enable row level security;
