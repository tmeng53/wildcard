# Admin MCP server

**Status: Ready** since the admin MCP server (#40), driven over HTTP by `scripts/api-journeys.sh admin-mcp`; CI's `supabase` job runs it.

An admin connects an MCP client to `/mcp`: the 401 points it at the protected resource metadata, Supabase Auth's OAuth 2.1 server sends the admin to our consent page (`/oauth/consent`), they sign in there and approve, then the client adds a meme, turns it off, reads the admin log, and reads and changes what the AI writes with (the draft and award settings). The app's own sign-in is refused at `/mcp`; a member not on the admin list is refused on the consent page, and gets nothing at `/mcp` even approving around it with their app session. Stand-ins: the client is a hand-registered public client driven with curl (Claude Code and claude.ai do the same steps), and the admin signs in on the consent page with email and password (`ADMIN_PASSWORD_SIGN_IN=on`), since local Supabase has no Sign in with Apple. The page's Apple button is covered only up to the redirect, by `consent-page.test.ts`.

Code: `api/apps/server/src/admin-mcp/` (`consent-page.ts` is the page), `api/packages/admins`, `api/packages/memes`, and the settings in `api/packages/disclaimer-drafts` and `api/packages/weekly-awards`.

## Drive it

```sh
scripts/api-journeys.sh admin-mcp 2>&1 | tee /tmp/verify-wildcard/<short sha>/admin-mcp-api.log
```

Signs up its own members and registers its own OAuth client from an empty stack. Needs `supabase start` (started after `[auth.oauth_server]` was enabled in `supabase/config.toml`), pnpm, curl, jq, node and psql.

## Expected output

Ids and the meme's suffix differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
admin-mcp: registered client <id>; admin=<id> on the admin list
admin-mcp: no token refused (401), pointing at metadata that names Supabase Auth
admin-mcp: the app's own sign-in refused (401 ADMIN_SIGN_IN_REQUIRED)
admin-mcp: a wrong password refused (401); admin signed in on the consent page, approved and got an OAuth token
admin-mcp: that sign-in can't answer again (401)
admin-mcp: initialized and listed the tools (list_admin_log,list_memes,add_memes,turn_off_meme,turn_on_meme,get_disclaimer_draft_settings,change_disclaimer_draft_settings,get_weekly_award_settings,change_weekly_award_settings)
admin-mcp: added the meme 班味<suffix> and it is in use
admin-mcp: turned it off, so it is no longer in use; an unknown meme refused (MEME_NOT_FOUND)
admin-mcp: the log holds the two changes, newest first, and no reads (add_memes,turn_off_meme)
admin-mcp: read the AI settings (openai/gpt-6-luna), turned drafts off and on, logged once each (false,true); an unknown provider refused
admin-mcp: the OAuth token refused by the app's routes (401 APP_SIGN_IN_REQUIRED)
admin-mcp: a member not on the admin list refused on the consent page (403)
admin-mcp: approving around the page still gets them nothing at /mcp (403 NOT_AN_ADMIN)
api-journeys: ok (admin-mcp)
```

A `FAIL:` line, a missing line or a different value is a FAIL. `registering the MCP client failed: ... OAuth server is disabled` means the local stack was started before the OAuth server was enabled: `supabase stop && supabase start`.

## Evidence

- `psql "$DB_URL" -c "select at, action from public.admin_actions where admin_id = '<admin id>' order by id"`: exactly `add_memes` then `turn_off_meme`, each with the arguments sent; no row for the reads or the refused call.
- `psql "$DB_URL" -c "select phrase, disabled_at from public.memes where phrase = '<phrase>'"`: one row, `disabled_at` set.

## Worth probing

- Open `/oauth/consent?authorization_id=<id>` in a browser: plain sign-in, then the approve page naming the client; the response carries `content-security-policy` with `frame-ancestors 'none'` and `cache-control: no-store`.
- A token from a client that registered itself: refused at `/auth/v1/oauth/clients/register` (dynamic registration is off).
- A change whose log row can't be written keeps nothing (covered by `admin-mcp.test.ts`; the log and the change share one transaction).
