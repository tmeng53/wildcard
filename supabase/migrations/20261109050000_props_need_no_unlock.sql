-- Every prop is every member's from the start (Tracy, 2026-11-09: 「道具以后都不用解锁」), so no
-- 练了 opens one any more. A training trigger can now be retired (`offered = false`), as a coach's
-- or the team's already could: it stops counting and opening anything, members keep what it
-- opened for them, and putting the rule again (put_unlock_rule) brings it back. The props' rules
-- are retired here; the app shows every prop open (`editor.json`).

alter table public.reward_triggers drop constraint reward_triggers_check;
alter table public.reward_triggers add constraint reward_triggers_check check (
  case kind
    when 'training' then sports is not null and after is not null and counts_from is not null
      and description is null
    when 'coach' then reward_kind = 'piece' and sports is null and after is null
      and counts_from is null
    else sports is null and after is null and counts_from is null and description is null
  end
);

update public.reward_triggers set offered = false
where reward_kind = 'prop' and kind = 'training' and offered;
