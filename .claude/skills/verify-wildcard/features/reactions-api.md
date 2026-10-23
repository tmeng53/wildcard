# Reactions through the API

**Status: Ready** since reactions (#53), driven over HTTP by `scripts/api-journeys.sh reactions`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

A teammate reacts to a member's check-in with an emoji, repeats it, changes it to another, and takes it off; the author sees it; the author can't react to their own, and someone outside the squad can't see the check-in at all. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/reactions.ts`.

## Drive it

```sh
scripts/api-journeys.sh reactions 2>&1 | tee /tmp/verify-wildcard/<short sha>/reactions-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
reactions: mate left ❤️ (201), again (200), then changed it to 😂 (200)
reactions: the author sees one reaction, mate's 😂
reactions: own check-in refused (400 OWN_CHECK_IN_REACTION), outsider sees nothing (404), text that isn't one emoji refused (400)
reactions: mate took it off (204, again 204), no row left
api-journeys: ok (reactions)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select * from public.check_in_reactions where check_in_id = '<post>'"`: no rows at the end (the script checks it).

## Worth probing

- Many teammates reacting at once: one row each, never two for one member.
- A reaction on a check-in sent only to another squad: 404.
