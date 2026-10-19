# A squad's Sunday 战报 through the API

**Status: Ready** since the week summary route, driven over HTTP by `scripts/api-journeys.sh week-summary`; CI's `supabase` job runs it. The app's recap card isn't built yet.

Three members in a fresh squad, all in a time zone where it is about noon. Ace plans every day as rest and trains anyway; writer and fan keep the default plan. Writer posts a 请假条 and fan reacts 笑死 to it. The fan reads this week's summary: the week is still being played (`final` false); ace is on the podium (`planCompleted`) and wears the crown with 1 trained day, since 1 is at least the 0 days planned; the best 请假条 is the writer's, by 1 reaction. Squad totals add up every member's counts (1 trained day of 10 planned, 2 check-ins, 1 笑死) and the fan's own reactions show the 笑死 as given. Next week isn't readable yet, and someone outside the squad is refused. Only winners are named; nobody is ranked. Stand-in: members sign up with email and password (the app uses Sign in with Apple).

Code: `api/apps/server/src/routes/week-summary.ts`, `api/packages/check-ins/src/domain/week-summary.ts` (the award and count registries), `api/packages/check-ins/src/use-cases/check-ins/week-summary.ts`.

## Drive it

```sh
scripts/api-journeys.sh week-summary 2>&1 | tee /tmp/verify-wildcard/<short sha>/week-summary-api.log
```

Signs up its own members from an empty stack. Needs `supabase start`, pnpm, curl, jq, node and psql.

## Expected output

Ids, dates and the time zone differ each run; the shape doesn't. Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
week-summary: squad=<id> in Etc/GMT+7 (2026-10-19) ace trained on a week planned all rest, writer posted a 请假条, fan laughed at it
week-summary: still being played; podium and crown ace (1 day), best 请假条 writer's (1 reaction)
week-summary: squad 1/10 days in 2 check-ins, 1 笑死, which the fan sees as given
week-summary: next week refused (400 WEEK_NOT_STARTED), outsider refused (403 SQUAD_NOT_JOINED)
api-journeys: ok (week-summary)
```

A `FAIL:` line, a missing line or a different value is a FAIL.

## Evidence

`<squad>` is the id on the first `week-summary:` line, not the one on `members:`.

- `psql "$DB_URL" -c "select member_id, day, kind from public.check_ins where id in (select check_in_id from public.check_in_squads where squad_id = '<squad>') order by created_at"`: two rows on the logged day, a `trained` from ace and a `disclaimer` from writer.
- `psql "$DB_URL" -c "select member_id, kind from public.check_in_reactions where check_in_id in (select check_in_id from public.check_in_squads where squad_id = '<squad>')"`: one `lol` from the fan.

## Worth probing

- Two members on the podium with the same trained days: both wear the crown.
- Two 请假条 with the same reactions: the earlier one wins.
- A reaction from someone who has left the squad: not counted.
- A member past their Sunday while another isn't: `final` stays false.
