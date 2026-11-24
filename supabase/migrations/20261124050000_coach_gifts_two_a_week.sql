-- Coach gifts (Tracy, 2026-11-24): the coach on its own gives a member at most two a week, and an
-- admin in its name any number. The count is the coach's own and lives in code (the unlocks
-- module), where a squad's wakes run one at a time; the database keeps only that a member holds
-- each piece once.
drop index public.grants_one_coach_gift_a_week;
