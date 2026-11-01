import type { CoachWakes } from '@wildcard/coach';
import { Hono } from 'hono';

import { JobTokenInvalidError, JobsOffError } from '../errors.js';
import { sendDailyProgress, type DailyProgressDependencies } from '../flows/daily-progress-push.js';
import { giveWeeklyAwards, type WeeklyAwardsDependencies } from '../flows/weekly-awards.js';
import { logAlso } from '../log.js';
import type { IsScheduler } from '../ports.js';
import { bearerToken } from '../require-caller.js';

/**
 * Work a scheduler starts, not the app: `POST /jobs/daily-progress-push`, meant to run every 15
 * minutes or so, `POST /jobs/weekly-awards`, meant to run every hour, and `POST /jobs/coach`,
 * meant to run every 10 minutes. Each call takes the
 * scheduler's bearer token: Cloud Scheduler's OIDC token on the hosted server, `JOBS_TOKEN`
 * on a local one. Not part of the app's contract, so not in openapi.json. Every entry a run logs
 * carries `job`, which the alerts `scripts/gcp-setup.sh` makes look for.
 */
export function jobs(deps: {
  readonly isScheduler: IsScheduler | undefined;
  readonly dailyProgress: DailyProgressDependencies;
  readonly weeklyAwards: WeeklyAwardsDependencies;
  /** The AI coach's wakes; undefined without an OpenAI key, and then the coach never wakes. */
  readonly coach?: CoachWakes;
}) {
  return new Hono()
    .use('/jobs/*', async (c, next) => {
      if (deps.isScheduler === undefined) throw new JobsOffError();
      if (!(await deps.isScheduler(bearerToken(c.req.header('authorization'))))) {
        throw new JobTokenInvalidError();
      }
      await next();
    })
    .post('/jobs/daily-progress-push', async (c) => {
      logAlso({ job: 'daily-progress-push' });
      const run = await sendDailyProgress(deps.dailyProgress);
      deps.dailyProgress.log.info('daily progress push run', { ...run });
      return c.json({ version: 1, ...run }, 200);
    })
    .post('/jobs/weekly-awards', async (c) => {
      logAlso({ job: 'weekly-awards' });
      const run = await giveWeeklyAwards(deps.weeklyAwards);
      deps.weeklyAwards.log.info('weekly awards run', { ...run });
      return c.json({ version: 1, ...run }, 200);
    })
    .post('/jobs/coach', async (c) => {
      logAlso({ job: 'coach' });
      const run =
        deps.coach === undefined
          ? { coaching: false, squads: 0, queued: 0, done: 0, failed: 0 }
          : await deps.coach.run();
      // A failed wake keeps why on its row (get_squad_coaching shows it) and is tried again.
      if (run.failed > 0) deps.weeklyAwards.log.warn('some coach wakes failed', { ...run });
      else deps.weeklyAwards.log.info('coach run', { ...run });
      return c.json({ version: 1, ...run }, 200);
    });
}
