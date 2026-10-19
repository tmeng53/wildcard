# The home screen's squad through the API

**Status: Ready** since the home summary's weekly plans, driven over HTTP by `scripts/api-journeys.sh home`; CI's `supabase` job runs it. The home screen itself isn't built yet and isn't covered here.

Two members in UTC share a squad. One plans to train every day and checks in a 练了; the other keeps the default plan (rest on Wednesday and Sunday) and opens the home screen. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/squad-today.ts`, `api/packages/check-ins/src/use-cases/check-ins/squad-today.ts`.

## Drive it

```sh
scripts/api-journeys.sh home 2>&1 | tee /tmp/verify-wildcard/<short sha>/home-api.log
```

It signs up its own two members, saves their profiles, creates the squad and joins by invite code, saves the lead's plan through `PUT /me/weekly-plans/{weekStart}`, then reads `GET /squads/{squadId}/today` as the rester. Needs `supabase start`, pnpm, curl, jq and psql.

## Expected output

Ids and dates differ each run; the shape doesn't. Copied from a real run (a Monday, so the rester isn't resting; on a Wednesday or Sunday the third `home:` line says `resting`):

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
home: squad=<id> lead=<id> rester=<id> today=<date>; lead plans 7 training days
home: lead trained today (201)
home: rester sees lead trained, themself not checked in, 本周 0/5, squad 1/12 (200)
home: outsider reading the squad's today refused (403 SQUAD_NOT_JOINED)
api-journeys: ok (home)
```

A `FAIL:` line, a missing line or a different value is a FAIL. The script checks the whole body: member order (checked in first), each member's day and planned rest, the today counts, 本周 x/y and the squad's x/y.

## Evidence

Check at the source, with the ids from the log:

- `psql "$DB_URL" -c "select member_id, week_start, payload from public.weekly_plans where member_id in ('<lead>', '<rester>')"`: one row for the lead, seven training days; none for the rester (the default plan).
- `select member_id, day, kind from public.check_ins c join public.check_in_squads s on s.check_in_id = c.id where s.squad_id = '<squad>'`: one `trained` row from the lead on today's date.

## Worth probing

- Members in time zones far apart (Pacific/Kiritimati and Pacific/Pago_Pago are 25 hours apart): each member's `day` is their own today, before 3am counting for the day before.
- A member on Sunday night while a teammate is already on Monday: each one's week, x and y are their own (`squadWeek` adds them up).
- A member who posts a 请假条 on a planned rest day: `disclaimer`, not `resting`.
- Everyone resting but nobody trained: `everyoneTrained` is false.
- A member who left the squad: not listed, not counted.
