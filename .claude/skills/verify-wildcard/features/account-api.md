# Profile and account deletion through the API

**Status: Ready** since account deletion (#54), driven over HTTP by `scripts/api-journeys.sh account`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

A new member has no profile, saves one (an unknown zone is refused), makes a squad with a teammate and posts a meal with a photo, then deletes their account: everything that is theirs goes, the squad stays with the teammate, and the old token can't delete again. The server runs without a Sign in with Apple key, so nothing is revoked at Apple. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/me.ts`, `api/apps/server/src/flows/delete-account.ts`.

## Drive it

```sh
scripts/api-journeys.sh account 2>&1 | tee /tmp/verify-wildcard/<short sha>/account-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
account: a new member has no profile, an unknown zone is refused (400 TIME_ZONE_UNKNOWN), America/Toronto saved
account: leaver made a squad with mate and posted a meal with a photo
account: deleted (204): no user, profile, check-in, membership, AI consent or photo left; the squad stays with mate
account: deleting again with the old token refused (401)
api-journeys: ok (account)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- The script counts the leaver's rows in `auth.users`, `public.profiles`, `public.profile_events`, `public.squad_membership_events`, `public.check_ins`, `public.squad_members` and `storage.objects`: all 0; the squad keeps one member.

## Worth probing

- Deleting while an upload is in flight: the folder ends empty.
- A member who signed in with Apple, once the Apple key is set: deleting without `appleAuthorizationCode` is refused.
