# A squad's today through the API

**Status: Ready** since the squad home data (#49), driven over HTTP by `scripts/api-journeys.sh squad-today`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

Three members in a fresh squad, all in a time zone where it is about noon. Runner and napper plan to train every day and rester to rest every day. Planned days count from the day a member joined, so the journey backdates the three members' join day (`profiles.created_at`) by 30 days and the whole week counts. The runner picks a catchphrase (口头禅) and makes a character (nickname and look); the napper's too-long catchphrase and one with a link are refused. The napper posts a 请假条 first, the runner then trains and eats a healthy meal, and the napper trains after all. The home screen's data shows each member's today in the home order (checked in today, by first check-in; then planned rest; then the rest), the counts, 本周 x/y against the plan and the squad's x/y. Each member carries their catchphrase and character, null when unset. A 练了 wins over an earlier 请假条, and 全员上场 counts a planned rest day. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/squad-today.ts`, `api/packages/members/src/domain/profile.ts` (the catchphrase and character), `api/packages/check-ins/src/use-cases/check-ins/squad-today.ts`.

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
squad-today: runner's catchphrase 冲就完了🔥 and character 跑跑 saved; napper's 11 characters and link refused (400)
squad-today: in Etc/GMT+1 (2026-10-19) runner trained and ate a healthy meal, napper posted a disclaimer first, rester plans to rest
squad-today: napper sees self first, then runner, then rester; 1 trained, 1 disclaimer, 1 resting; 本周 0/7, squad 1/14
squad-today: napper sees runner's catchphrase 冲就完了🔥, null for self and rester
squad-today: napper sees runner's character 跑跑 (shiba in a jersey), none for self and rester
squad-today: napper trained after all, so 练了 wins over the disclaimer; with rester resting, everyone trained
squad-today: outsider refused (403 SQUAD_NOT_JOINED)
api-journeys: ok (squad-today)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select member_id, day, kind from public.check_ins where member_id in ('<runner>', '<napper>') order by created_at"`: four rows, all on the logged day.
- `psql "$DB_URL" -c "select member_id, catchphrase, nickname, look from public.profiles where member_id in ('<runner>', '<napper>', '<rester>')"`: the runner's are `冲就完了🔥`, `跑跑` and a look with `"version": 1`; the others are null.
- `psql "$DB_URL" -c "select member_id, week_start from public.weekly_plans where member_id in ('<runner>', '<napper>', '<rester>')"`: three rows, all on the logged day's Monday.

## Worth probing

- Members in different time zones, one already past midnight: each has their own day.
- A squad where everyone is on a planned rest day and nobody trained: not 全员上场.
- A check-in sent to another squad: counts in `me.week` but not in this squad's today.
