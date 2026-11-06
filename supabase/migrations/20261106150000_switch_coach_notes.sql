-- A line the AI coach reads while a switch is on (Tracy, 2026-11-06: 「做节日处理的时候，那个教练
-- 也要知道今天过节」), such as 「今天是感恩节」, so the coach knows the moment from data and
-- no holiday is in code. Never shown in the app. The switches' log keeps it with each change,
-- since a change logs the whole row.
alter table public.switches
  add column coach_note text
    check (
      coach_note is null
      or (pg_catalog.btrim(coach_note) <> '' and char_length(coach_note) <= 120 and coach_note !~ '[\r\n]')
    );
