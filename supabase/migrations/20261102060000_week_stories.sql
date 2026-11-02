-- Each squad's weekly 战报 (每周战报), frozen at the week's awards (Sunday 8pm): who was in the
-- squad then, that week's scene and every page without AI, written once and never changed
-- (Tracy, 2026-10-30), so nothing that happens later (a member joining or leaving, a late
-- check-in, a reaction, a new look or scene) changes a past 战报. The AI's titles arrive later
-- in weekly_award_winners. Every rule lives in the API's weekly-awards module; the database
-- keeps keys and shapes only.

-- The squad's part: its name and scene that week, and the pages that are the squad's.
create table public.week_stories (
  squad_id uuid not null references public.squads (id) on delete cascade,
  -- The week's Monday.
  week_start date not null check (extract(isodow from week_start) = 1),
  -- Stored JSON with its shape's version at the top: {"version": 1, ...}. The API owns the
  -- shape and parses it on every read.
  story jsonb not null check (coalesce(jsonb_typeof(story -> 'version') = 'number', false)),
  written_at timestamptz not null default now(),
  primary key (squad_id, week_start)
);

-- Each member's part: everyone in the squad at the awards, in the order they joined, with
-- their character and their week. A deleted account takes its row with it.
create table public.week_story_members (
  squad_id uuid not null,
  week_start date not null,
  member_id uuid not null references auth.users (id) on delete cascade,
  position integer not null check (position >= 0),
  page jsonb not null check (coalesce(jsonb_typeof(page -> 'version') = 'number', false)),
  primary key (squad_id, week_start, member_id),
  foreign key (squad_id, week_start)
    references public.week_stories (squad_id, week_start) on delete cascade
);

create index week_story_members_member_id_idx on public.week_story_members (member_id);

-- Each member's posts on the story's pages (their most-reacted check-in, the squad's best
-- 请假条 when it was theirs), one row each with its words and photo paths, so deleting the
-- post takes them with it.
create table public.week_story_posts (
  squad_id uuid not null,
  week_start date not null,
  member_id uuid not null,
  role text not null check (role in ('hottest', 'bestDisclaimer')),
  check_in_id uuid not null references public.check_ins (id) on delete cascade,
  post jsonb not null check (coalesce(jsonb_typeof(post -> 'version') = 'number', false)),
  primary key (squad_id, week_start, member_id, role),
  foreign key (squad_id, week_start, member_id)
    references public.week_story_members (squad_id, week_start, member_id) on delete cascade
);

create index week_story_posts_check_in_id_idx on public.week_story_posts (check_in_id);

-- Frozen: rows are only ever added. Any update or truncate is refused, and any delete except
-- the cascade when the squad, a member's account or, for a post, the post is deleted.
create function public.week_stories_frozen() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  raise exception 'week_stories is frozen' using errcode = '42501';
end;
$$;

create function public.week_story_members_frozen() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from public.squads where id = old.squad_id)
    or not exists (select 1 from auth.users where id = old.member_id)
  ) then
    return old;
  end if;
  raise exception 'week_story_members is frozen' using errcode = '42501';
end;
$$;

create function public.week_story_posts_frozen() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and (
    not exists (select 1 from public.check_ins where id = old.check_in_id)
    or not exists (
      select 1 from public.week_story_members
      where squad_id = old.squad_id and week_start = old.week_start and member_id = old.member_id
    )
  ) then
    return old;
  end if;
  raise exception 'week_story_posts is frozen' using errcode = '42501';
end;
$$;

create trigger week_stories_frozen
  before update or delete on public.week_stories
  for each row execute function public.week_stories_frozen();
create trigger week_stories_no_truncate
  before truncate on public.week_stories
  for each statement execute function public.week_stories_frozen();
create trigger week_story_members_frozen
  before update or delete on public.week_story_members
  for each row execute function public.week_story_members_frozen();
create trigger week_story_members_no_truncate
  before truncate on public.week_story_members
  for each statement execute function public.week_story_members_frozen();
create trigger week_story_posts_frozen
  before update or delete on public.week_story_posts
  for each row execute function public.week_story_posts_frozen();
create trigger week_story_posts_no_truncate
  before truncate on public.week_story_posts
  for each statement execute function public.week_story_posts_frozen();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.week_stories enable row level security;
alter table public.week_story_members enable row level security;
alter table public.week_story_posts enable row level security;
