# Daily progress push through the API

**Status: Ready** since the daily progress push (#78), driven over HTTP by `scripts/api-journeys.sh daily-push`; CI's `supabase` job runs it. The app's push text and its notification service extension aren't covered here.

Four members in a time zone where it is about 8pm, each with a phone. Runner, cheerer and resting are in a squad; loner has none. Resting turns the daily push off. Runner trains and cheerer cheers it. The scheduler's job then handles runner and cheerer (something to tell them), loner quietly (no squad, so nothing to tell), and resting not at all; a second run handles no one again. No push is sent: CI has no APNs key, so the two with news count as `unsent`. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/flows/daily-progress-push.ts`, `api/apps/server/src/routes/jobs.ts`, `api/apps/server/src/routes/push-settings.ts`.

## Drive it

```sh
scripts/api-journeys.sh daily-push 2>&1 | tee /tmp/verify-wildcard/<short sha>/daily-push-api.log
```

Signs up its own members. Needs `supabase start`, pnpm, curl, jq, node and psql. The server gets a fresh `JOBS_TOKEN` from `scripts/lib/api-server.sh`.

## Expected output

Ids and the zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
daily-push: on until turned off, then off (200); a missing switch refused (400)
daily-push: in Etc/GMT, runner trained and cheerer cheered them
daily-push: a member's token refused (401); the job handled runner and cheerer, loner quietly, resting not at all
daily-push: a second run handled no one again
api-journeys: ok (daily-push)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select * from public.daily_pushes where day = '<their day>'"`: one row per handled member, `quiet` true only for loner.
- The server log has one `daily progress push run` line per run, with `due`, `sent`, `unsent`, `quiet`, `skipped` and `failed`. Other members in a shared local database can add to those counts; the rows for the journey's own members are the check.

## Worth probing

- The server without `JOBS_TOKEN`: the job answers 503 `JOBS_OFF`.
- Several runs at once: each member is still handled once (`daily_pushes`' primary key), the others count them as `skipped`.
- A member before 6pm on their clock, or without a phone: not due.
