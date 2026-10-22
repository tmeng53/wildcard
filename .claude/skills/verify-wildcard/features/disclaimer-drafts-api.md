# AI 请假条 drafts through the API

**Status: Ready** since AI drafts (#41), driven over HTTP by `scripts/api-journeys.sh disclaimer-drafts`; CI's `supabase` job runs it. It runs the server without `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, as CI does, so it never calls a model provider. Drafts written by the model are covered by the route tests, which replay recorded OpenAI and Claude responses through each adapter (`api/apps/server/src/routes/disclaimer-drafts.test.ts`). The app's screen isn't covered here.

A member taps "write it for me" on a rest-day post. Without a key the server answers 503 and the app shows its dice; a reason that speaks of self-harm gets the care line either way, and never AI copy. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/disclaimer-drafts.ts`, `api/packages/disclaimer-drafts`.

## Drive it

```sh
scripts/api-journeys.sh disclaimer-drafts 2>&1 | tee /tmp/verify-wildcard/<short sha>/disclaimer-drafts-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq and psql.

## Expected output

Ids differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
disclaimer-drafts: no key, so 503 DISCLAIMER_WRITER_UNAVAILABLE (the app shows its dice), no error logged
disclaimer-drafts: a self-harm reason gets the care line (200), with or without a key
disclaimer-drafts: a member who hasn't agreed to the AI terms refused (400 AI_CONSENT_REQUIRED)
disclaimer-drafts: an unknown style refused (400), a signed-out caller refused (401)
disclaimer-drafts: no batch counted
api-journeys: ok (disclaimer-drafts)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

Check at the source, with the ids from the log:

- `psql "$DB_URL" -c "select count(*) from public.disclaimer_draft_requests where member_id = '<me>'"`: 0. A batch that showed nothing gives its place back, and the care line never takes one.
- The server log has no `"severity":"ERROR"` line for the no-key 503s; it logs `no key for LLM_PROVIDER: AI drafts are off` once at startup.

## Worth probing

- 「不想活动」 (don't feel like moving) is not self-harm: it must reach the model, not get the care line.
- With a key (a fake one, pointed at a local stub replaying `api/apps/server/src/test-kit/openai/*.json`, or `anthropic/*.json` with `LLM_PROVIDER=anthropic`): 3 drafts per batch, and the 7th counted batch in 24 hours answers 429 `DISCLAIMER_DRAFTS_USED_UP`. About 3 in 10 prompts carry one `本周梗` line, for a meme in use that suits the style; the rest carry none, and none ever lists the whole library.
- A draft with body metrics, calories or macros is never shown: the batch answers 503 and doesn't count.
