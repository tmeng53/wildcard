-- Art the app downloads (Tracy, 2026-11-04): character pieces, props, moves and scene pictures
-- added through admin tools reach every installed app without a release. Each file lives in
-- the public `art` bucket under its content's SHA-256 (`<sha256>.<ext>`), so a name never
-- changes what it holds and the app keeps each one it downloaded for good. `art_files` says
-- which file stands at each path of the app's art tree, the same paths the app bundles
-- (`avatar/art/top/warmup-tee/torso.svg`); a path the table doesn't name keeps the bundled
-- file. Data only, never code (App Store guideline 2.5.2): SVG in the art's subset, keyframe
-- JSON and PNG, checked by the API before a row is written.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('art', 'art', true, 2097152, array['image/svg+xml', 'application/json', 'image/png']);

-- One row per change, never changed or removed, so the table is its own log: the newest row of
-- a path says what stands there now, and a row without a file takes the path back to the
-- bundled one. The newest row's id is the art's generation: the app swaps to a new set of
-- files only once it has all of a generation's.
create table public.art_files (
  id bigint generated always as identity primary key,
  path text not null check (
    path ~ '^(avatar|coaches|scenes|openings)(/[A-Za-z0-9][A-Za-z0-9_@.-]{0,63}){1,6}\.(svg|json|png)$'
    and path !~ '\.\.'
  ),
  -- The file's SHA-256 in hex, its name in the bucket with the path's extension; null when the
  -- path goes back to the bundled file.
  sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
  size int check (size between 1 and 2097152),
  -- The lowest version of the app's rig that can draw it; older builds leave it out.
  rig_version int not null default 1 check (rig_version between 1 and 1000),
  -- The admin who put it.
  changed_by uuid not null,
  changed_at timestamptz not null default now(),
  check ((sha256 is null) = (size is null))
);

create index art_files_path_id_idx on public.art_files (path, id desc);

create function public.art_files_append_only() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger art_files_append_only
  before update or delete on public.art_files
  for each row execute function public.art_files_append_only();
create trigger art_files_no_truncate
  before truncate on public.art_files
  for each statement execute function public.art_files_append_only();

-- Only the API reads and writes it; the app reads the list through the public catalog.
alter table public.art_files enable row level security;
