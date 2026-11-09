-- Takes back the team rewards given on 2026-11-09 to try the feedback thank-yous on TestFlight
-- (Tracy, 2026-11-09: 收回来): the 捉虫队 and 点子王 badges and the 共建捉虫网 and 共建灯泡头箍
-- pieces, given with `give_reward` between 11:16 and 11:18 UTC (the only grants of them so far).
-- Nobody opened, claimed, wore or equipped them, and no notice was written for them. A grant is
-- otherwise never taken back, and the guard is back on before this migration ends; `admin_actions`
-- keeps the record that they were given.

alter table public.grants disable trigger grants_append_only;

delete from public.grants
where via = 'team'
  and (reward_kind, reward_id) in (
    ('badge', 'bug-hunter'), ('badge', 'idea-king'),
    ('piece', 'thanks-bugnet'), ('piece', 'thanks-bulb')
  )
  and at >= '2026-11-09 11:16:00+00'
  and at < '2026-11-09 11:18:00+00';

alter table public.grants enable trigger grants_append_only;
