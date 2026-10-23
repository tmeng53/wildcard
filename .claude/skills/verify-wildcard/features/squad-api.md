# Squads through the API

**Status: Ready** since the squad API, driven over HTTP by `scripts/api-journeys.sh squad`; CI's `supabase` job runs it. The app's screens for it come with the sign-up flow and aren't covered here.

A member creates a squad with only a name, after agreeing to the AI consent copy (`PUT /me/ai-consent`, which creating or joining needs), a friend joins with its invite code, a newcomer previews and joins by the code typed loosely (lower case, with a dash), then leaves. The web invite page's preview (`GET /public/squad-invites/{code}`) answers without a token, with the members' looks but never names or ids. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/squads.ts`, `api/packages/squads`.

## Drive it

```sh
scripts/api-journeys.sh squad 2>&1 | tee /tmp/verify-wildcard/<short sha>/squad-api.log
```

Every journey's setup creates the squad through `PUT /squads/{id}` and joins the mate through `POST /squad-invites/{code}/accept`, so `check-in` and `photo-upload` exercise these routes too. Needs `supabase start`, pnpm, curl, jq and psql.

## Expected output

Ids and codes differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
squad: making a squad before agreeing to the AI terms refused (400 AI_CONSENT_REQUIRED)
members: me=<id> mate=<id> outsider=<id> squad=<id>
squad: mate's squads list <id>, name trimmed, me then mate
squad: newcomer previews <code typed as abcd-EFGH>: 早八跑团, 2 members
squad: anyone previews <code typed as abcd-EFGH> without signing in; an unknown code answers 404
squad: joining before agreeing refused (400 AI_CONSENT_REQUIRED); another copy version refused (400 AI_CONSENT_COPY_OUTDATED)
squad: newcomer agreed to the AI terms at <time>; agreeing again keeps it
squad: newcomer joined (201), joining again answered 200
squad: an unknown code refused (404 INVITE_CODE_UNKNOWN)
squad: outsider reading the squad refused (403 SQUAD_NOT_JOINED)
squad: newcomer left (204) and can't read it any more
api-journeys: ok (squad)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

Check at the source, with the ids from the log:

- `psql "$DB_URL" -c "select id, name, invite_code, created_by from public.squads where id = '<squad>'"`: one row, name `早八跑团` (trimmed), an 8-letter code with none of 0, O, 1, I, L, created by me.
- `select member_id from public.squad_members where squad_id = '<squad>' order by joined_at`: me, then mate; the newcomer left, so no row for them.
- `select member_id, copy_version, given_at from public.ai_consents where member_id in ('<me>', '<mate>')`: one row each, copy version 1. Deleting an account (`DELETE /me`) deletes its rows.

## Worth probing

Each must be refused with a problem naming its reason, and nothing may change:

- A ninth member joining (`SQUAD_FULL`), including nine at once: never more than 8 rows.
- A member already in 3 squads creating or joining another (`SQUAD_LIMIT_REACHED`), including several at once.
- `PUT /squads/{id}` again with another name, or by another member (`SQUAD_ID_CONFLICT`); the same body again answers 200.
- More than 30 public previews from one client address in 10 minutes (429 `REQUESTS_TOO_FREQUENT`, with `Retry-After`); the server counts the last `X-Forwarded-For` entry, so a client's own entries before it change nothing.
- Consent to a version other than the current one (400 `AI_CONSENT_COPY_OUTDATED`), or `copyVersion` 0 or a string (400 `REQUEST_INVALID`): no row. There is no route to withdraw it (`DELETE /me/ai-consent` is 404).
- A create or join the member already made, repeated after their consent row is gone (as after a copy bump): still 200, while a new squad or join is refused (`AI_CONSENT_REQUIRED`).
- A name that is blank, on two lines or over 20 characters (400 `REQUEST_INVALID`).
