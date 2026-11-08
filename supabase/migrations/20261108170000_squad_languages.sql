-- A squad's language (小队语言): what the AI writes everything the whole squad reads in, its
-- coach's 战术板, the weekly awards and the coach's name. What one member reads keeps their own
-- app's language. The captain picks it, and it counts at once; the squad's language is its newest
-- row, and a squad with none reads its captain's app language, as every squad did before. Never
-- changed: the table is its own log.
create table public.squad_languages (
  id bigint generated always as identity primary key,
  squad_id uuid not null references public.squads (id) on delete cascade,
  language text not null check (language in ('zh-Hans', 'zh-Hant', 'en')),
  -- Null once the setter deletes their account.
  set_by uuid references auth.users (id) on delete set null,
  set_at timestamptz not null default now()
);

create index squad_languages_squad_idx on public.squad_languages (squad_id, id);
create index squad_languages_set_by_idx on public.squad_languages (set_by);

create function public.squad_languages_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The squad's cascade, and the setter's account deletion clearing who set it, go through.
  if tg_op = 'DELETE' and not exists (select 1 from public.squads where id = old.squad_id) then
    return old;
  end if;
  if tg_op = 'UPDATE'
    and new.set_by is null
    and old.set_by is not null
    and not exists (select 1 from auth.users where id = old.set_by)
    and (new.id, new.squad_id, new.language, new.set_at)
      = (old.id, old.squad_id, old.language, old.set_at)
  then
    return new;
  end if;
  raise exception 'squad_languages is append-only' using errcode = '42501';
end;
$$;

create trigger squad_languages_append_only
  before update or delete on public.squad_languages
  for each row execute function public.squad_languages_append_only();

create trigger squad_languages_no_truncate
  before truncate on public.squad_languages
  for each statement execute function public.squad_languages_append_only();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.squad_languages enable row level security;
