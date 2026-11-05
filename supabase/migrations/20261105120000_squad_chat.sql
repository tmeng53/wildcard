-- The squad's group chat (群聊, Tracy's approved design, 2026-11-04): members write to the whole
-- squad, the squad's coach answers when someone @s it or replies to it and posts its daily
-- 战术板 line there, and members react, reply, report and delete their own messages.
-- As with every table, only our API reads and writes it; who may write, how long a message may
-- be and who sees which messages (a member sees those sent since they joined) are the API's.

-- One row per message. A member's message is named by the app, so a retry saves it once; the
-- coach's are named here. A message is never changed (there is no editing), so the table is its
-- own log; deleting one removes it, as deleting a post or an account removes that person's data.
create table public.squad_messages (
  id uuid primary key default gen_random_uuid(),
  -- Its place in the squad's chat, oldest first: what pages and read markers count by.
  seq bigint generated always as identity unique,
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- Who wrote it: a member, or the squad's coach.
  member_id uuid references auth.users (id) on delete cascade,
  coach_id text references public.coaches (id),
  check ((member_id is null) <> (coach_id is null)),
  -- `text` is written; `note` is the coach's 战术板 line of `note_day`, one a squad a day.
  kind text not null check (kind in ('text', 'note')),
  note_day date,
  check ((kind = 'note') = (note_day is not null)),
  check (kind = 'text' or coach_id is not null),
  text text not null check (char_length(text) between 1 and 2000),
  -- The message it replies to, when it does. Deleting that one leaves this a plain message.
  reply_to uuid references public.squad_messages (id) on delete set null,
  -- Whom it @s: members by id, and the coach.
  mentions uuid[] not null default '{}' check (cardinality(mentions) <= 8),
  mentions_coach boolean not null default false,
  created_at timestamptz not null default now()
);

create index squad_messages_squad_seq_idx on public.squad_messages (squad_id, seq desc);
create index squad_messages_member_id_idx on public.squad_messages (member_id);
create index squad_messages_reply_to_idx on public.squad_messages (reply_to);
create unique index squad_messages_one_note_a_day on public.squad_messages (squad_id, note_day)
  where kind = 'note';
-- The coach answers a member's message once, however many times its wake is tried.
create unique index squad_messages_one_coach_answer on public.squad_messages (reply_to)
  where coach_id is not null and kind = 'text';

-- A message is written once and may be deleted, never changed. The one change allowed is the
-- `reply_to` the deletion of the message it replied to clears.
create function public.squad_messages_unchanged()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id = old.id
    and new.seq = old.seq
    and new.squad_id = old.squad_id
    and new.member_id is not distinct from old.member_id
    and new.coach_id is not distinct from old.coach_id
    and new.kind = old.kind
    and new.note_day is not distinct from old.note_day
    and new.text = old.text
    and new.mentions = old.mentions
    and new.mentions_coach = old.mentions_coach
    and new.created_at = old.created_at
    and new.reply_to is null
    and old.reply_to is not null
    and not exists (select 1 from public.squad_messages where id = old.reply_to)
  then
    return new;
  end if;
  raise exception '% can''t be changed', tg_table_name using errcode = '42501';
end;
$$;

create trigger squad_messages_unchanged
  before update on public.squad_messages
  for each row execute function public.squad_messages_unchanged();

-- Members' reactions: any one emoji per member a message, like 动态's. Only the emoji that stands
-- is kept, as with a check-in's reactions.
create table public.squad_message_reactions (
  message_id uuid not null references public.squad_messages (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 32),
  at timestamptz not null default now(),
  primary key (message_id, member_id)
);

create index squad_message_reactions_member_id_idx on public.squad_message_reactions (member_id);

-- Guards the chat's own logs: a row is never changed or removed, except when its account, its
-- squad or its message goes and the cascade takes it.
create function public.squad_chat_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from auth.users where id = old.member_id)
    or not exists (select 1 from public.squads where id = (to_jsonb(old) ->> 'squad_id')::uuid)
    or (
      to_jsonb(old) ? 'message_id'
      and not exists (
        select 1 from public.squad_messages where id = (to_jsonb(old) ->> 'message_id')::uuid
      )
    )
  ) then
    return old;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

-- Messages members reported (举报), for the admins. The report keeps what was reported, so a
-- message its writer deletes afterwards can still be judged; the reporter's account takes it.
create table public.squad_message_reports (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  message_id uuid references public.squad_messages (id) on delete set null,
  -- Who wrote the message, and what it said, as it was reported.
  reported_member_id uuid references auth.users (id) on delete set null,
  reported_text text not null check (char_length(reported_text) between 1 and 2000),
  member_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now(),
  unique (message_id, member_id)
);

create index squad_message_reports_member_id_idx on public.squad_message_reports (member_id);

-- Only the cascades change a report: the reporter's account or the squad removes it, the
-- message's deletion or its writer's account clears what points at them.
create function public.squad_message_reports_guard()
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
  if tg_op = 'UPDATE'
    and new.id = old.id
    and new.squad_id = old.squad_id
    and new.reported_text = old.reported_text
    and new.member_id = old.member_id
    and new.at = old.at
    and (new.message_id is not distinct from old.message_id or new.message_id is null)
    and (new.reported_member_id is not distinct from old.reported_member_id
      or new.reported_member_id is null)
  then
    return new;
  end if;
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger squad_message_reports_guard
  before update or delete on public.squad_message_reports
  for each row execute function public.squad_message_reports_guard();

-- How each member is told of a squad's messages (the bell's pull-down in the chat): `mentions`
-- (a push when someone @s them or replies to them, the default), `all` (every message) or
-- `none`. A row per change, the newest being the setting now, so the table is its own log.
create table public.squad_chat_alerts (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  alerts text not null check (alerts in ('mentions', 'all', 'none')),
  at timestamptz not null default now()
);

create index squad_chat_alerts_newest_idx on public.squad_chat_alerts (squad_id, member_id, id desc);
create index squad_chat_alerts_member_id_idx on public.squad_chat_alerts (member_id);

create trigger squad_chat_alerts_append_only
  before update or delete on public.squad_chat_alerts
  for each row execute function public.squad_chat_log_append_only();

create trigger squad_chat_alerts_no_truncate
  before truncate on public.squad_chat_alerts
  for each statement execute function public.squad_chat_log_append_only();

-- How far each member has read a squad's chat, for the count on its button: a row each time it
-- moves on, the newest being how far they read.
create table public.squad_chat_reads (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  read_through bigint not null,
  at timestamptz not null default now()
);

create index squad_chat_reads_newest_idx on public.squad_chat_reads (squad_id, member_id, id desc);
create index squad_chat_reads_member_id_idx on public.squad_chat_reads (member_id);

create trigger squad_chat_reads_append_only
  before update or delete on public.squad_chat_reads
  for each row execute function public.squad_chat_log_append_only();

create trigger squad_chat_reads_no_truncate
  before truncate on public.squad_chat_reads
  for each statement execute function public.squad_chat_log_append_only();

create trigger squad_message_reports_no_truncate
  before truncate on public.squad_message_reports
  for each statement execute function public.squad_chat_log_append_only();

-- Live events (`20261104010000_live_events.sql`): each member of the squad who can see the
-- message hears it as it commits: `chat` for a new message or one whose reactions changed (by
-- its `seq`), `chatDeleted` for one deleted (by its id, since it is gone).
create function public.squad_messages_live_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  message_id uuid;
  squad uuid;
  message_seq bigint;
  written timestamptz;
  event_kind text := 'chat';
begin
  if tg_table_name = 'squad_message_reactions' then
    if tg_op = 'DELETE' then
      message_id := old.message_id;
    else
      message_id := new.message_id;
    end if;
    select squad_id, seq, created_at into squad, message_seq, written
    from public.squad_messages where id = message_id;
    -- The message went with it (its deletion tells of that).
    if not found then
      return null;
    end if;
  elsif tg_op = 'DELETE' then
    message_id := old.id;
    squad := old.squad_id;
    message_seq := old.seq;
    written := old.created_at;
    event_kind := 'chatDeleted';
  else
    message_id := new.id;
    squad := new.squad_id;
    message_seq := new.seq;
    written := new.created_at;
  end if;
  perform pg_notify(
    'live_events',
    json_build_object(
      'version', 1,
      'member', squad_members.member_id,
      'kind', event_kind,
      'id', message_seq,
      'squad', squad,
      'message', message_id
    )::text
  )
  from public.squad_members
  where squad_members.squad_id = squad
    and squad_members.joined_at <= written;
  return null;
end;
$$;

create trigger squad_messages_live_event
  after insert or delete on public.squad_messages
  for each row execute function public.squad_messages_live_event();

create trigger squad_message_reactions_live_event
  after insert or update or delete on public.squad_message_reactions
  for each row execute function public.squad_messages_live_event();

-- A coach's wake for a member's chat message that @s it or replies to it: the message it answers,
-- whose deletion takes the wake. The answer is a message of its own, one a message
-- (`squad_messages_one_coach_answer`).
alter table public.coach_wakes
  drop constraint coach_wakes_reason_check,
  add constraint coach_wakes_reason_check
    check (reason in ('checkIn', 'daily', 'comment', 'chat')),
  add column chat_message_id uuid references public.squad_messages (id) on delete cascade,
  add constraint coach_wakes_chat_check check ((reason = 'chat') = (chat_message_id is not null));

create unique index coach_wakes_one_per_chat_message on public.coach_wakes (squad_id, chat_message_id)
  where reason = 'chat';

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_messages enable row level security;
alter table public.squad_message_reactions enable row level security;
alter table public.squad_message_reports enable row level security;
alter table public.squad_chat_alerts enable row level security;
alter table public.squad_chat_reads enable row level security;
