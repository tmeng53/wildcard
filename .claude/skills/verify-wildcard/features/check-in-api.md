# Check-in through the API

**Status: Ready** since the check-in API (#25), driven over HTTP by `scripts/api-journeys.sh check-in`; CI's `supabase` job runs it. The app's screen for it is in #26 and isn't covered here.

A member saves a 练了 check-in to their squad, a squad-mate posts today's 请假条, and both read the squad back. The app makes each check-in's id, so a retry answers with the saved one. Stand-in: members sign up with email and password (the app uses Sign in with Apple). The squad is made through the squad routes (`squad-api.md`).

Code: `api/apps/server/src/routes/check-ins.ts`, `api/packages/check-ins`.

## Drive it

```sh
scripts/api-journeys.sh check-in 2>&1 | tee /tmp/verify-wildcard/<short sha>/check-in-api.log
```

It builds the API, starts the real server (`api/apps/server/dist/src/main.js`) on a free port against local Supabase, signs up three members (me, a squad-mate, an outsider); I create a squad and the mate joins it by its invite code. It needs `supabase start`, pnpm, curl, jq and psql, and stops the server when it ends.

## Expected output

Ids differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
check-in: saved trained <id> with 40 minutes (201)
check-in: 601 minutes refused (400 REQUEST_INVALID)
check-in: retry answered with the saved one (200)
check-in: different contents under the same id refused (409 CHECK_IN_ID_CONFLICT)
check-in: mate posted today's disclaimer <id> (201)
check-in: a second disclaimer today refused (409 DISCLAIMER_ALREADY_POSTED)
check-in: outsider posting to the squad refused (403 SQUAD_NOT_JOINED)
check-in: mate sees both in the squad list (2 check-ins), minutes included
check-in: outsider reading the squad refused (403 SQUAD_NOT_JOINED)
check-in: signed-out read refused (401)
check-in: my list holds only my own (<id>)
api-journeys: ok (check-in)
```

A `FAIL:` line (it prints the answer and the server's log), a missing line or a different value is a FAIL.

## Evidence

Check at the source, with the ids from the log:

- `psql "$DB_URL" -c "select id, member_id, day, kind, payload from public.check_ins where member_id in ('<me>', '<mate>')"`: exactly two rows, the 练了 (payload `{"version": 1, "sport": "custom", "customSport": "飞盘", "minutes": 40, "caption": "累但爽"}`) and the 请假条; the refused calls left nothing.
- `select * from public.check_in_squads where check_in_id in ('<id>', '<id>')`: each lists the squad at position 1.

## Worth probing

Each must be refused with a problem naming its reason, and nothing may change:

- A `createdAt` more than 48 hours ago (`CHECK_IN_TOO_OLD`) or ahead of the server's clock (`CHECK_IN_IN_THE_FUTURE`).
- A `day` the member hadn't reached at `createdAt` in their profile's time zone (3am rule), or more than one day before it; with no profile, more than one day from `createdAt`'s UTC date (`CHECK_IN_DAY_MISMATCH`).
- A member who left the squad: their check-ins drop out of the squad's list.
- A day range longer than 31 days (400).
