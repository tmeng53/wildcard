# 请假条 replies through the API

**Status: Ready** since 请假条 replies, driven over HTTP by `scripts/api-journeys.sh replies`; CI's `supabase` job runs it. The app's screens for it aren't covered here.

A member posts a 今日请假条; a teammate replies 准了 (`approved`), repeats it, changes it to 抱抱 (`hug`) and also leaves a 😂 reaction, which is kept apart; the author sees the one reply. A 练了 takes no replies, the author can't reply to their own 请假条, and someone outside the squad can't see it at all. Taking the reply off leaves the reaction. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/replies.ts`, `api/packages/check-ins/src/use-cases/check-ins/reply-to-disclaimer.ts`.

## Drive it

```sh
scripts/api-journeys.sh replies 2>&1 | tee /tmp/verify-wildcard/<short sha>/replies-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
replies: mate replied 准了 (201), again (200), changed it to 抱抱 (200), and laughed at it too
replies: the author sees one reply, mate's 抱抱, apart from the reaction
replies: a 练了 refused (400 NOT_A_DISCLAIMER), own 请假条 refused (400 OWN_DISCLAIMER_REPLY), outsider sees nothing (404), unknown kind refused (400)
replies: mate took it off (204, again 204), no reply row left, the reaction kept
api-journeys: ok (replies)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select * from public.disclaimer_replies where check_in_id = '<excuse>'"`: no rows at the end, while `check_in_reactions` still holds the mate's 😂 (the script checks both).

## Worth probing

- Many teammates replying at once: one row each, never two for one member.
- A reply from a member who shares the 请假条 through one squad only: the author sees it, a teammate in another squad doesn't.
- The 战报's best 请假条 still counts reactions only, never replies.
