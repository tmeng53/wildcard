-- 补打卡 (Tracy, 2026-11-03): a check-in may count for a day up to 7 days before the one the
-- member posted it on. `day` stays the day it counts for; `posted_day` is the member's own
-- day (to 3am, in their time zone) when they made it, which orders and pages the squad's feed.
-- Earlier check-ins counted for the day they were made on, or within one day of it, so they
-- were posted on the day they count for.
alter table public.check_ins add column posted_day date;
update public.check_ins set posted_day = day;
alter table public.check_ins alter column posted_day set not null;

-- The API always gives it. A row written without one (a test, a hand fix) was posted on the
-- day it counts for.
create function public.check_in_posted_day_default()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.posted_day := coalesce(new.posted_day, new.day);
  return new;
end;
$$;

create trigger check_ins_posted_day_default
before insert on public.check_ins
for each row execute function public.check_in_posted_day_default();

-- Never counted for a day after the one it was posted on.
alter table public.check_ins add constraint check_ins_posted_on_or_after_day
check (coalesce(posted_day >= day, false));

create index check_ins_posted_day_idx on public.check_ins (posted_day desc, created_at desc);
