-- At most one 今日免责声明 per member per day (Tracy, 2026-10-18). `day` is the
-- member's local day with its 3am grace, as the app sets it. Deleting it (on the
-- same day) frees the day for a new one.
create unique index check_ins_one_disclaimer_a_day
on public.check_ins (member_id, day)
where kind = 'disclaimer';
