-- @ in comments (Tracy, 2026-11-05, feedback #58): a comment may @ up to 8 people who can see
-- its post (each is told) and the squad's coach (who answers it, as a reply to it).

-- Whom a comment @s, in the order written. Written with the comment and never changed, so the
-- table is its own log; deleting the comment or a mentioned account removes the row.
create table public.check_in_comment_mentions (
  comment_id uuid not null references public.check_in_comments (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  position smallint not null check (position between 0 and 7),
  primary key (comment_id, member_id),
  unique (comment_id, position)
);

create index check_in_comment_mentions_member_id_idx
  on public.check_in_comment_mentions (member_id);

create function public.check_in_comment_mentions_unchanged()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% can''t be changed', tg_table_name using errcode = '42501';
end;
$$;

create trigger check_in_comment_mentions_unchanged
  before update on public.check_in_comment_mentions
  for each row execute function public.check_in_comment_mentions_unchanged();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.check_in_comment_mentions enable row level security;

-- The coach a comment @s (@毛头), by id, when it does. Coaches are never deleted.
alter table public.check_in_comments
  add column mentions_coach text references public.coaches (id);

-- A comment is still never changed: the one change allowed stays the `reply_to` an account's
-- deletion clears.
create or replace function public.check_in_comments_unchanged()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id = old.id
    and new.check_in_id = old.check_in_id
    and new.member_id = old.member_id
    and new.text = old.text
    and new.commented_at = old.commented_at
    and new.reply_to_coach is not distinct from old.reply_to_coach
    and new.mentions_coach is not distinct from old.mentions_coach
    and new.reply_to is null
    and old.reply_to is not null
    and not exists (select 1 from auth.users where id = old.reply_to)
  then
    return new;
  end if;
  raise exception '% can''t be changed', tg_table_name using errcode = '42501';
end;
$$;
