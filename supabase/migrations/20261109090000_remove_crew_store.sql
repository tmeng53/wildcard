-- Removes the `crew` store, a hidden-store try for the team's thank-you pieces that the trigger model
-- replaced (Tracy, 2026-11-09: 删掉crew商店): the store, its one piece row (`thanks-bulb`, which
-- stays a reward the team and the `idea-adopted` event give), the training rule that piece got
-- there, and the `crew` switch, each with its log rows, so replaying the logs never brings them
-- back. Nothing else is touched: a store, piece, rule or switch is otherwise never deleted, and each
-- guard is back on before this migration ends.

alter table public.reward_triggers disable trigger reward_triggers_keep_their_start;
alter table public.reward_trigger_events disable trigger reward_trigger_events_append_only;
alter table public.pieces disable trigger pieces_keep_their_ids;
alter table public.piece_events disable trigger piece_events_append_only;
alter table public.stores disable trigger stores_keep_their_ids;
alter table public.store_events disable trigger store_events_append_only;
alter table public.switches disable trigger switches_keep_their_ids;
alter table public.switch_events disable trigger switch_events_append_only;

-- The training rule on `thanks-bulb`, logged as a trigger or, from before triggers, as an unlock
-- rule; its `event` and `team` triggers stay.
delete from public.reward_trigger_events
where (value ->> 'reward_id' = 'thanks-bulb' and value ->> 'kind' = 'training')
  or (value ->> 'item_id' = 'thanks-bulb' and value ->> 'replaces' = 'unlock_rule_events');
delete from public.reward_triggers
where reward_kind = 'piece' and reward_id = 'thanks-bulb' and kind = 'training';

-- `thanks-bulb`'s place in the store; nobody claimed it there (piece_claims would refuse this).
delete from public.piece_events where value ->> 'id' = 'thanks-bulb';
delete from public.pieces where id = 'thanks-bulb' and store_id = 'crew';

-- The store, once no piece is left in it.
delete from public.store_events where value ->> 'id' = 'crew';
delete from public.stores where id = 'crew';

-- Its switch, unless something else follows it or a campaign owns it.
delete from public.switch_events
where value ->> 'id' = 'crew'
  and not exists (select 1 from public.scenes where switch_id = 'crew')
  and not exists (select 1 from public.stores where switch_id = 'crew')
  and not exists (select 1 from public.pieces where switch_id = 'crew')
  and not exists (select 1 from public.campaigns where value -> 'switches' ? 'crew');
delete from public.switches
where id = 'crew'
  and not exists (select 1 from public.scenes where switch_id = 'crew')
  and not exists (select 1 from public.stores where switch_id = 'crew')
  and not exists (select 1 from public.pieces where switch_id = 'crew')
  and not exists (select 1 from public.campaigns where value -> 'switches' ? 'crew');

alter table public.reward_triggers enable trigger reward_triggers_keep_their_start;
alter table public.reward_trigger_events enable trigger reward_trigger_events_append_only;
alter table public.pieces enable trigger pieces_keep_their_ids;
alter table public.piece_events enable trigger piece_events_append_only;
alter table public.stores enable trigger stores_keep_their_ids;
alter table public.store_events enable trigger store_events_append_only;
alter table public.switches enable trigger switches_keep_their_ids;
alter table public.switch_events enable trigger switch_events_append_only;
