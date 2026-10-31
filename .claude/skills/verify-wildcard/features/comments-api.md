# Comments through the API

**Status: Ready** since comments (#334), driven over HTTP by `scripts/api-journeys.sh comments`; CI's `supabase` job runs it. The app's screens for it are covered by `FeedUITests.testComments`.

A teammate comments on a member's check-in and retries it; the author replies to them; both read the comments oldest first, in the list and on the post's own page; an outsider sees nothing; a reply to an outsider, a comment over 100 characters and deleting someone else's are refused; the writer deletes theirs, twice. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/comments.ts`, `api/packages/check-ins/src/use-cases/check-ins/comments.ts`.

## Drive it

```sh
scripts/api-journeys.sh comments 2>&1 | tee /tmp/verify-wildcard/<short sha>/comments-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
comments: mate wrote one (201), the retry saved nothing new (200), another text under its id refused (409)
comments: the author replied to mate (201); both read them oldest first, here and on the post's page
comments: outsider sees nothing (404), a reply to an outsider (400), 101 characters (400) and deleting mate's (403) refused
comments: mate deleted theirs (204, again 204), one row left
api-journeys: ok (comments)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

- `psql "$DB_URL" -c "select * from public.check_in_comments where check_in_id = '<post>'"`: only the author's reply at the end (the script checks it).

## Worth probing

- A member who left the squad deletes their own old comment: 204; someone else's there: 404.
- A comment from a member of another squad on the same post: hidden from viewers who aren't in that squad.
