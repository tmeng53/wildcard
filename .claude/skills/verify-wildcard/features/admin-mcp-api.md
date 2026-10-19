# Admin MCP server

**Status: Ready** since the admin MCP server (#40), driven over HTTP by `scripts/api-journeys.sh admin-mcp`; CI's `supabase` job runs it.

An admin connects an MCP client to `/mcp`: the 401 points it at the protected resource metadata, the admin signs in through Supabase Auth's OAuth 2.1 server and approves the client, then adds a meme, turns it off and reads the admin log. The app's own sign-in, and a member not on the admin list, are refused. Stand-ins: the client is a hand-registered public client driven with curl (Claude Code and claude.ai do the same steps), the member signs up with email and password, and the script approves through Supabase's `/oauth/authorizations` API, which is what the consent screen calls.

Code: `api/apps/server/src/admin-mcp/`, `api/packages/admins`, `api/packages/memes`.

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
admin-mcp: admin approved the client on the consent screen and got an OAuth token
admin-mcp: initialized and listed the tools (list_admin_log,list_memes,add_memes,turn_off_meme,turn_on_meme)
admin-mcp: added the meme 班味<suffix> and it is in use
admin-mcp: turned it off, so it is no longer in use; an unknown meme refused (MEME_NOT_FOUND)
admin-mcp: the log holds the two changes, newest first, and no reads (add_memes,turn_off_meme)
admin-mcp: the OAuth token refused by the app's routes (401 APP_SIGN_IN_REQUIRED)
admin-mcp: a member not on the admin list refused, OAuth token and all (403 NOT_AN_ADMIN)
api-journeys: ok (admin-mcp)
```

A `FAIL:` line, a missing line or a different value is a FAIL. `registering the MCP client failed: ... OAuth server is disabled` means the local stack was started before the OAuth server was enabled: `supabase stop && supabase start`.

## Evidence

- `psql "$DB_URL" -c "select at, action from public.admin_actions where admin_id = '<admin id>' order by id"`: exactly `add_memes` then `turn_off_meme`, each with the arguments sent; no row for the reads or the refused call.
- `psql "$DB_URL" -c "select phrase, disabled_at from public.memes where phrase = '<phrase>'"`: one row, `disabled_at` set.

## Worth probing

- A token from a client that registered itself: refused at `/auth/v1/oauth/clients/register` (dynamic registration is off).
- A change whose log row can't be written keeps nothing (covered by `admin-mcp.test.ts`; the log and the change share one transaction).
