-- A squad goes with the account of its last member (Tracy, 2026-10-24): nobody can open a squad
-- with no members, so keeping it would only keep what its members wrote (its name, its awards).
-- A squad its last member left stays, ended, as before. The account's cascade runs it, so it
-- happens in the same transaction as the deletion, whoever deletes the user.

-- A check-in another member sent to the squad (before they left it) stays theirs, without the
-- squad it can no longer be read in.
alter table public.check_in_squads
  drop constraint check_in_squads_squad_id_fkey,
  add constraint check_in_squads_squad_id_fkey
    foreign key (squad_id) references public.squads (id) on delete cascade;

-- Security definer: Auth's own role deletes the user, and has no rights on public.
create function public.delete_squad_left_by_deleted_account() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from auth.users where id = old.member_id)
    and not exists (select 1 from public.squad_members where squad_id = old.squad_id)
  then
    delete from public.squads where id = old.squad_id;
  end if;
  return null;
end;
$$;

create trigger delete_squad_left_by_deleted_account
  after delete on public.squad_members
  for each row execute function public.delete_squad_left_by_deleted_account();

revoke execute on function public.delete_squad_left_by_deleted_account() from public, anon, authenticated;
