-- A meme can expire (Tracy, 2026-11-02): one tied to a moment, like the clocks going back, gets
-- the day it stops being used; one people keep saying gets none and stays in use until it is
-- turned off. The fixed 4 weeks after approval is gone, so every meme already here has none.
-- Changes to memes are now logged too (`meme_events`, below).
alter table public.memes
  add column expires_at timestamptz,
  add constraint memes_expires_after_approval check (expires_at > approved_at);

-- Every change to a meme (approved, its expiry set, moved or cleared, turned off or on) is
-- logged here in the same statement, with the meme's full new row, and none for a save that
-- changed nothing. The admin who made it is in `admin_actions`, written in the same
-- transaction. The log starts with the memes already here.
create table public.meme_events (
  id bigint generated always as identity primary key,
  op text not null check (op in ('INSERT', 'UPDATE')),
  value jsonb not null,
  -- The database role that made it.
  by_role text not null default current_user,
  at timestamptz not null default now()
);

insert into public.meme_events (op, value)
select 'INSERT', pg_catalog.to_jsonb(m) from public.memes m order by m.approved_at, m.phrase;

create function public.log_meme_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.meme_events (op, value) values (tg_op, pg_catalog.to_jsonb(new));
  return null;
end;
$$;

create trigger memes_logged
  after insert on public.memes
  for each row execute function public.log_meme_change();
create trigger memes_changes_logged
  after update on public.memes
  for each row when (old is distinct from new) execute function public.log_meme_change();

create function public.meme_events_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'meme_events is append-only' using errcode = '42501';
end;
$$;

create trigger meme_events_append_only
  before update or delete on public.meme_events
  for each row execute function public.meme_events_append_only();
create trigger meme_events_no_truncate
  before truncate on public.meme_events
  for each statement execute function public.meme_events_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.meme_events enable row level security;
