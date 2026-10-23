import { Hono } from 'hono';

import { JobTokenInvalidError, JobsOffError } from '../errors.js';
import { sendDailyProgress, type DailyProgressDependencies } from '../flows/daily-progress-push.js';
import { giveWeeklyAwards, type WeeklyAwardsDependencies } from '../flows/weekly-awards.js';
import type { IsScheduler } from '../ports.js';
import { bearerToken } from '../require-caller.js';

/**
 * Work a scheduler starts, not the app: `POST /jobs/daily-progress-push`, meant to run every 15
 * minutes or so, and `POST /jobs/weekly-awards`, meant to run every hour. Each call takes the
 * scheduler's bearer token: Cloud Scheduler's OIDC token on the hosted server, `JOBS_TOKEN`
 * on a local one. Not part of the app's contract, so not in openapi.json.
 */
export function jobs(deps: {
  readonly isScheduler: IsScheduler | undefined;
  readonly dailyProgress: DailyProgressDependencies;
  readonly weeklyAwards: WeeklyAwardsDependencies;
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
      const run = await sendDailyProgress(deps.dailyProgress);
      deps.dailyProgress.log.info('daily progress push run', { ...run });
      return c.json({ version: 1, ...run }, 200);
    })
    .post('/jobs/weekly-awards', async (c) => {
      const run = await giveWeeklyAwards(deps.weeklyAwards);
      deps.weeklyAwards.log.info('weekly awards run', { ...run });
      return c.json({ version: 1, ...run }, 200);
    });
}
