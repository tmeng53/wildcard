-- Saving the same check-in twice succeeds. The app retries a save whenever it can't
-- tell whether the last attempt landed (offline sync, a dropped connection), so a
-- retry of a check-in that is already saved must look like success, not an error.
--
-- Before, the retry reached the insert and failed on whichever check ran first: for a
-- check-in with photos that was "another check-in already uses this photo", which the
-- app can't tell apart from a real conflict. Now the id is looked up first.
create or replace function public.create_check_in(check_in jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  payload_key text;
  audience_size int;
  saved public.check_ins;
begin
  if (check_in ->> 'version') is distinct from '1' then
    raise exception 'unsupported check-in version: %', check_in ->> 'version'
      using errcode = '22023';
  end if;
  if (check_in ->> 'member')::uuid is distinct from auth.uid() then
    raise exception 'a check-in''s member must be the caller' using errcode = '42501';
  end if;
  payload_key := case check_in ->> 'kind'
    when 'trained' then 'training'
    when 'healthyMeal' then 'meal'
    when 'cheatMeal' then 'meal'
    when 'disclaimer' then 'disclaimer'
  end;
  if payload_key is null then
    raise exception 'unknown check-in kind: %', check_in ->> 'kind' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_object_keys(check_in) k
      where k not in ('version', 'id', 'member', 'day', 'createdAt', 'audience', 'kind', payload_key)) > 0
  then
    raise exception 'check-in keys don''t match its kind' using errcode = '22023';
  end if;
  if jsonb_typeof(check_in -> 'audience') is distinct from 'array' then
    raise exception 'a check-in needs its audience' using errcode = '22023';
  end if;
  audience_size := jsonb_array_length(check_in -> 'audience');
  if audience_size not between 1 and 3 then
    raise exception 'a check-in goes to 1 to 3 squads, not %', audience_size using errcode = '22023';
  end if;
  if (select count(distinct value::uuid) from jsonb_array_elements_text(check_in -> 'audience')) <> audience_size then
    raise exception 'a check-in''s audience lists each squad once' using errcode = '22023';
  end if;

  -- Already saved? The caller sees only their own check-ins here, so this finds a
  -- retry of theirs and nothing of anyone else's. A retry is the same check-in sent
  -- again; the same id with different contents is a bug in the app, so it is refused.
  select * into saved from public.check_ins where id = (check_in ->> 'id')::uuid;
  if found then
    if saved.member_id = (check_in ->> 'member')::uuid
       and saved.kind = (check_in ->> 'kind')::public.check_in_kind
       and saved.day = (check_in ->> 'day')::date
       and saved.created_at = (check_in ->> 'createdAt')::timestamptz
       and saved.payload = check_in -> payload_key
       and array(select squad_id from public.check_in_squads where check_in_id = saved.id order by position)
           = array(select value::uuid from jsonb_array_elements_text(check_in -> 'audience') with ordinality
                   order by ordinality)
    then
      return;
    end if;
    raise exception 'a different check-in is already saved with this id' using errcode = '23505';
  end if;

  insert into public.check_ins (id, member_id, day, created_at, kind, payload, version)
  values (
    (check_in ->> 'id')::uuid,
    (check_in ->> 'member')::uuid,
    (check_in ->> 'day')::date,
    (check_in ->> 'createdAt')::timestamptz,
    (check_in ->> 'kind')::public.check_in_kind,
    check_in -> payload_key,
    1
  );
  insert into public.check_in_squads (check_in_id, squad_id, position)
  select (check_in ->> 'id')::uuid, squad::uuid, position
  from jsonb_array_elements_text(check_in -> 'audience') with ordinality as a (squad, position);
end;
$$;
