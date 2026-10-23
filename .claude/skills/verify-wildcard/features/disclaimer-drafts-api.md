# AI 请假条 drafts through the API

**Status: Ready** since AI drafts (#41), driven over HTTP by `scripts/api-journeys.sh disclaimer-drafts`; CI's `supabase` job runs it. It runs the server without `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, as CI does, so it never calls a model provider. Drafts written by the model are covered by the route tests, which replay recorded OpenAI and Claude responses through each adapter (`api/apps/server/src/routes/disclaimer-drafts.test.ts`). The app's screen isn't covered here.

A member taps "write it for me" on a rest-day post. Without a key the server answers 503 and the app shows its dice; whether a reason speaks of self-harm is the model's to judge (no word list on the server), and then it answers the care line, never AI copy. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

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
disclaimer-drafts: a self-harm reason is the model's to judge, so with no key it is 503 too
disclaimer-drafts: a member who hasn't agreed to the AI terms refused (400 AI_CONSENT_REQUIRED)
disclaimer-drafts: an unknown style refused (400), a signed-out caller refused (401)
disclaimer-drafts: no batch counted
api-journeys: ok (disclaimer-drafts)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

Check at the source, with the ids from the log:

- `psql "$DB_URL" -c "select count(*) from public.disclaimer_draft_requests where member_id = '<me>'"`: 0. A batch that showed nothing gives its place back.
- The server log has no `"severity":"ERROR"` line for the no-key 503s; it logs `no language model key: AI drafts are off and weekly awards stay pending` once at startup.

## Worth probing

- A reason about self-harm reaches the model like any other; the recorded `self-harm` answer gives `{"version":1,"kind":"care"}`.
- With a key (a fake one, pointed at a local stub replaying `api/apps/server/src/test-kit/openai/*.json`, or `anthropic/*.json` after setting the model to `anthropic/…` with the admin tool `change_disclaimer_draft_settings`): 3 drafts per batch, and the 7th counted batch in 24 hours answers 429 `DISCLAIMER_DRAFTS_USED_UP` (the settings' `batchesPerDay`). About 3 in 10 prompts (the settings' `memeChance`) carry one `本周梗` line, for a meme in use that suits the style; the rest carry none, and none ever lists the whole library.
- Settings apply to the next request with no restart: `writing: false` makes every request answer 503 `DISCLAIMER_WRITER_UNAVAILABLE` without counting, and the request names the settings' model and instructions.
- The server checks only a batch's shape (exactly 3 distinct drafts, 15 to 80 characters, one line each); a batch out of shape answers 503 and doesn't count. What the drafts say is the prompt's job: there are no word checks on them.
