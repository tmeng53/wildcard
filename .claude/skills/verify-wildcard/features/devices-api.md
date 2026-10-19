# Push devices through the API

**Status: Ready** since push devices (#53), driven over HTTP by `scripts/api-journeys.sh devices`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

A member registers their phone for push, again; a teammate signs in on the same phone and it moves to them; the first member removing it does nothing, the teammate signing out removes it. No push is sent: CI has no APNs key. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/devices.ts`.

## Drive it

```sh
scripts/api-journeys.sh devices 2>&1 | tee /tmp/verify-wildcard/<short sha>/devices-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
devices: me registered a phone (200, again 200)
devices: mate signed in on the same phone, so it moved to mate
devices: me removing it did nothing (204); mate signing out removed it (204)
devices: a token that isn't hex refused (400)
api-journeys: ok (devices)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select * from public.push_devices where token = '<token>'"`: no row at the end (the script checks each step).

## Worth probing

- Registering without signing in: 401.
- A token of the right characters but too short or too long: 400.
