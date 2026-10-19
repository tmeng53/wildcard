# A squad's today through the API

**Status: Ready** since the squad home data (#49), driven over HTTP by `scripts/api-journeys.sh squad-today`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

Two members in a fresh squad, both in a time zone where it is about noon: one trains and eats a healthy meal, the other posts a 请假条 and then trains after all. The home screen's data shows each member's today in join order and the counts, and a 练了 wins over an earlier 请假条. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/squad-today.ts`, `api/packages/check-ins/src/use-cases/check-ins/squad-today.ts`.

## Drive it

```sh
scripts/api-journeys.sh squad-today 2>&1 | tee /tmp/verify-wildcard/<short sha>/squad-today-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
squad-today: in Etc/GMT (2026-10-19) runner trained and ate a healthy meal, napper posted a disclaimer
squad-today: napper sees runner trained, self on a disclaimer; 1 trained, 1 disclaimer, squad week 1
squad-today: napper trained after all, so 练了 wins over the disclaimer and everyone trained
squad-today: outsider refused (403 SQUAD_NOT_JOINED)
api-journeys: ok (squad-today)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select member_id, day, kind from public.check_ins where member_id in ('<runner>', '<napper>') order by created_at"`: four rows, all on the logged day.

## Worth probing

- Members in different time zones, one already past midnight: each has their own day.
- A check-in sent to another squad: counts in `me.week` but not in this squad's today.
