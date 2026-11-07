-- The Apple Health sync guide's screenshots (guides/<wearable>-<n>@3x.png) are art too: put with
-- the admin tools, downloaded by the app, never bundled. The art tree's paths gain that root.
alter table public.art_files drop constraint art_files_path_check;
alter table public.art_files add constraint art_files_path_check check (
  path ~ '^(avatar|coaches|scenes|openings|guides)(/[A-Za-z0-9][A-Za-z0-9_@.-]{0,63}){1,6}\.(svg|json|png)$'
  and path !~ '\.\.'
);
