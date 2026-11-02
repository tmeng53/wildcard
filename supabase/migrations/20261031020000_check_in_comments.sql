-- Comments on check-ins (动态评论): what teammates, and the author, write under a post, one
-- level deep. Reactions stay apart: a member may leave both.
-- As with every table, only our API reads and writes it; who may comment and how long a
-- comment may be are the API's to check.

-- The app names each comment, so a retry saves it once. A comment is never changed once
-- written (there is no editing), so the table is its own log. Deleting one removes it, as
-- deleting a post or an account removes that person's data.
create table public.check_in_comments (
  id uuid primary key,
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  member_id uuid not null references auth.users (id) on delete cascade,
  text text not null check (char_length(text) between 1 and 1000),
  -- Whom the comment replies to (回复 Mia：…), when it does. A deleted account leaves the
  -- comment as a plain one.
  reply_to uuid references auth.users (id) on delete set null,
  commented_at timestamptz not null
);

create index check_in_comments_check_in_id_idx on public.check_in_comments (check_in_id, commented_at);
create index check_in_comments_member_id_idx on public.check_in_comments (member_id);

-- A comment is written once and may be deleted, never changed. The one change allowed is the
-- `reply_to` an account's deletion clears.
create function public.check_in_comments_unchanged()
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
    and new.reply_to is null
    and old.reply_to is not null
    and not exists (select 1 from auth.users where id = old.reply_to)
  then
    return new;
  end if;
  raise exception '% can''t be changed', tg_table_name using errcode = '42501';
end;
$$;

create trigger check_in_comments_unchanged
  before update on public.check_in_comments
  for each row execute function public.check_in_comments_unchanged();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.check_in_comments enable row level security;
