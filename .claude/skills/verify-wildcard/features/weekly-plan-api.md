# Weekly plan through the API

**Status: Ready** since the weekly plan (#50), driven over HTTP by `scripts/api-journeys.sh weekly-plan`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

A member with no profile can't save a plan; once they save one in a time zone where it is about noon, this week reads as the default, next week saves (and saving again changes nothing), the week after carries it over, and past, too-far and non-Monday weeks are refused. Next week's 饮食小目标 save (own words trimmed) and are logged once however often they are saved; they don't carry over, and this week's are refused. Every week says the member's first week, the one they joined. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/weekly-plans.ts`, `api/packages/check-ins/src/domain/weekly-plan.ts`, `api/packages/check-ins/src/domain/fuel-goal.ts`.

## Drive it

```sh
scripts/api-journeys.sh weekly-plan 2>&1 | tee /tmp/verify-wildcard/<short sha>/weekly-plan-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
weekly-plan: no profile yet, so saving is refused (400 TIME_ZONE_NOT_SET)
weekly-plan: this week (2026-10-19, Etc/GMT) is the default, rest on Wednesday and Sunday
weekly-plan: next week (2026-10-26) saved, custom sport trimmed; saving again changes nothing
weekly-plan: the week after (2026-11-02) carries it over
weekly-plan: last week refused (400 WEEK_OVER), 5 weeks ahead refused (400 WEEK_TOO_FAR_AHEAD), a Tuesday refused (400)
weekly-plan: one row stored, for 2026-10-26
weekly-plan: next week's 饮食小目标 saved (own words trimmed), logged once though saved twice, not carried over; this week's saved and logged; last week's refused (400 WEEK_OVER); first week 2026-10-19
api-journeys: ok (weekly-plan)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select week_start, payload from public.weekly_plans where member_id = '<planner>'"`: one row, next week's Monday, with `飞盘` trimmed.
- `psql "$DB_URL" -c "select week_start, payload from public.fuel_goal_events where member_id = '<planner>'"`: one row, next week's two goals.

## Worth probing

- In the current week after the join day: changing a day before today (`PLAN_DAY_STARTED`); today or a later day turning into a rest day is allowed and logged.
- Today's day in a zone where it is just before 3am: it still counts as the day before.
