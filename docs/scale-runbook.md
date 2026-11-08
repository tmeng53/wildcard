# Scale runbook: a launch brings hundreds of members at once

What breaks first if a few hundred to 1,000 members (about 200 squads) arrive at once, and what to change. Each limit was checked on 2026-11-08 against the repo and the hosted projects; re-check a number before you rely on it.

"Do now" means change it before a launch is announced, because it fails at once or can't be changed fast. "When needed" means watch it and change it when you get close to the limit; each one is a setting you can change in minutes.

## Do now

| What | Limit now | When it breaks | Change | Cost |
| --- | --- | --- | --- | --- |
| Supabase plan | **Free**: 500 MB database, 1 GB storage, 5 GB egress a month, Nano compute (shared CPU, 0.5 GB RAM, 60 Postgres connections) | Photos (about 250 KB each, 1080 px JPEG, about 2 a member a day) fill 1 GB in about 2 days at 1,000 members, and 5 GB of egress in about 2 days of squadmates viewing them. Past the quota, Supabase restricts the project. | Upgrade the organization to Pro (dashboard → Billing). | $25 a month, including 8 GB database, 100 GB storage, 250 GB egress and $10 of compute credit. |
| Supabase compute | Nano | 1,000 members' reads plus the hourly and 10-minute jobs on a shared half-CPU | With Pro, pick Small (2 GB RAM, 90 connections) in dashboard → Compute. It restarts the database for about 2 minutes, so do it before launch. | About $5 a month after Pro's credit. |
| Supabase pooler pool size | 15 server connections, shared by the transaction pooler (every request) and each instance's `LISTEN` session (session pooler) | With 10 Cloud Run instances, 10 `LISTEN` sessions can hold most of the 15, and requests queue for the rest. | After Small compute, raise the pool size to about 40 in dashboard → Database → Connection pooling. | Free. |
| Cloud Run concurrency and instances | Was 80 requests an instance and 3 instances: 240 open apps (each open app holds one `GET /me/events` stream) | The 241st open app waits or gets a 429. | `--concurrency 250 --max-instances 10` in `.github/workflows/deploy.yml` (this PR), then run the deploy. Holds 2,500 open apps; min instances stays 0. | Billing follows instances actually running: about $50–100 a month at 1,000 members, the same as before. |
| OpenAI budget | No budget cap on the project (on the launch list) | A bug or abuse could spend without limit. The coach's own caps (below) cover only the coach. | Set a monthly budget of about $300 on the OpenAI project and turn on its hard limit, so requests stop at the budget instead of only alerting. | Free. |

## When needed

| What | Limit now | When it breaks | Change | Cost |
| --- | --- | --- | --- | --- |
| Coach daily cap, all squads | `dailyCapMicros` 5,000,000 ($5 a New York day) | About 200 active squads use about $3 a day. Past $5, every coach goes quiet until the next day. | `change_coach_settings` with a higher `dailyCapMicros`, such as 10,000,000. | Up to the new cap: $10 a day is $300 a month at most. |
| Coach daily cap, one squad | `squadDailyCapMicros` 50,000 ($0.05) | A very chatty squad (about 70 coach wakes in a day) | Leave it; it is per squad by design. | None. |
| Coach wake throughput | The 10-minute job runs 4 squads at once for 150 s (`AT_ONCE`, `RUN_BUDGET_MS` in `coach-wakes.ts`); check-in and comment wakes run inside their own requests | The 3am dream and the 6am daily wake queue one wake a squad at once: about 40 daily wakes a run, so 200 squads take about 50 minutes, still before the 8am notes. Past about 400 squads, notes come late. | Raise `AT_ONCE` (code change), staying within OpenAI's rate limit. | None beyond tokens. |
| Weekly awards job | Squads 4 at a time, no time budget; Cloud Scheduler gives up on the call after 300 s (`--attempt-deadline` in `scripts/gcp-setup.sh`) | At Sunday 8pm about 200 squads on one clock take about 15 minutes. Squads not done when the call is cut are tried again on the next hourly run, so some 战报 titles show up an hour or two late (the 战报 itself shows at once). | Raise `--attempt-deadline` to `1800s` and rerun `scripts/gcp-setup.sh`, or give the job a time budget like the coach's. | None. |
| OpenAI rate limits | Set by the account's usage tier, which rises with total spend; check Settings → Limits for `gpt-6-luna` | A burst (6am daily wakes plus Sunday awards) above the tier's requests or tokens a minute: calls fail and are retried on the next run. | Check the tier's limits before launch; prepaying credit moves the account up a tier. | Prepaid credit is spent later, not extra. |
| Supabase Auth rate limits | Per IP address (sign-ins, token refreshes) | Members each sign in from their own phone, so only many members behind one address (an office Wi-Fi at a launch event) | Raise them in dashboard → Authentication → Rate limits. | Free. |
| Public route rate limits | In each instance's memory: invite lookups 30 per 10 minutes and catalog reads 300 per 10 minutes, per IP | Many phones on one Wi-Fi opening the same invite at an event | Raise the numbers in `apps/server/src/main.ts`. | None. |
| Cloud Run instance size | 1 vCPU, 512 MiB (defaults) | Memory over about 80% with 250 streams per instance; Cloud Monitoring shows it | `--memory 1Gi` in `deploy.yml` | About 10% more per running instance. |
| Supabase storage and egress on Pro | 100 GB storage, 250 GB egress a month | About 6 months of photos at 1,000 members; egress at about 2,500 members | Nothing: Pro bills overage ($0.021 a GB stored, $0.09 a GB egress). Set a spend cap or alert in Billing. | Small. |

## Not a limit at 1,000 members

- **APNs push**: no published rate limit at this volume; one HTTP/2 connection carries every push.
- **Cloud Scheduler**: 3 jobs, inside the free 3 jobs an account.
- **Pub/Sub**: not used by the server yet; its free 10 GB a month is far above our events.
- **Cloud Logging and Monitoring**: well under the free 50 GB a month of logs.
- **Sentry**: the free plan's 5,000 errors a month. In an outage, errors past that are dropped, and Cloud Logging still has them.
- **Website** (Vercel): static pages; the invite page reads one public route.
- **Apple developer account**: $99 a year, whatever the number of members.

## Cost at 1,000 members, once "Do now" is done

About $175 a month typical ($70 low, $310 high): AI coach $20–150 (capped), Cloud Run $10–100, Supabase Pro with Small compute $30–40, other AI $3–10, Apple $8, domain and small Google Cloud items $2–5.

Sources: [Cloud Run concurrency](https://cloud.google.com/run/docs/about-concurrency), [Cloud Run max instances](https://cloud.google.com/run/docs/configuring/max-instances-limits), [Supabase compute and connections](https://supabase.com/docs/guides/platform/compute-and-disk), [Supabase connection pooler](https://supabase.com/docs/guides/database/connecting-to-postgres#connection-pooler), [Supabase Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits), [Cloud Scheduler attempt deadline](https://cloud.google.com/scheduler/docs/reference/rest/v1/projects.locations.jobs#Job.FIELDS.attempt_deadline), [OpenAI rate limits](https://platform.openai.com/docs/guides/rate-limits).
