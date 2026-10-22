# A squad's weekly AI awards and Sunday story through the API

**Status: On main, not drivable over HTTP alone.** Nothing schedules the awards run until the hourly job route lands (it reuses the `POST /jobs/...` setup of the daily progress push). Until then, drive the run from its flow test, or call `giveWeeklyAwards` from the built server as `main.ts` wires it.

After Sunday 8pm New York, every member who checked in that week before then gets 1 to 3 titles (at most 6 characters each), each with a 颁奖词 (at most 24) and a move. The awards are written once per squad-week; each winner gets one `push.weeklyAwards.ready` that doesn't say what they won. While the model fails, the story is `pending`: no `titles`, everything else (`hottest`) as usual. A member's 「催一下主办方」 (`POST …/story/nudge`) tells the admins once per failed try with the squad's name, the tries and the error's name and status. Stand-in: no model key, so a run fails the way production does without credit.

Code: `api/packages/weekly-awards/`, `api/apps/server/src/flows/weekly-awards.ts`, `api/apps/server/src/routes/week-story.ts`.

## Drive it

```sh
cd api && DATABASE_URL=… SUPABASE_URL=… SUPABASE_PUBLISHABLE_KEY=… SUPABASE_SECRET_KEY=… \
  npx vitest run apps/server/src/flows/weekly-awards.test.ts packages/weekly-awards 2>&1 \
  | tee /tmp/verify-wildcard/<short sha>/weekly-awards-api.log
```

The values come from `npx supabase status -o env` (`DB_URL`, `API_URL`, `PUBLISHABLE_KEY`, `SECRET_KEY`). The tests sign up their own members.

## Expected output

```text
 Test Files  4 passed (4)
```

Any failed test is a FAIL.

## Evidence to check

- `select squad_id, week_start, given_at, failed_attempts, last_error, nudged_failures from public.weekly_awards`: a failing week has `given_at` null, a count, and an error like `RateLimitError 429 insufficient_quota`. It never holds a member's words.
- `select member_id, position, award from public.weekly_award_winners`: one row per winner, `award` with `"version": 1`. No row for a member who didn't check in. A deleted account leaves no row.
