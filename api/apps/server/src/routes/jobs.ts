import { timingSafeEqual } from 'node:crypto';

import { Hono } from 'hono';

import { JobTokenInvalidError, JobsOffError } from '../errors.js';
import { sendDailyProgress, type DailyProgressDependencies } from '../flows/daily-progress-push.js';
import { giveWeeklyAwards, type WeeklyAwardsDependencies } from '../flows/weekly-awards.js';
import { bearerToken } from '../require-caller.js';

/**
 * Work a scheduler starts, not the app: `POST /jobs/daily-progress-push`, meant to run every 15
 * minutes or so, and `POST /jobs/weekly-awards`, meant to run every hour. Each call takes
 * `Authorization: Bearer <JOBS_TOKEN>`. Not part of the app's contract, so not in openapi.json.
 */
export function jobs(deps: {
  readonly jobsToken: string | undefined;
  readonly dailyProgress: DailyProgressDependencies;
  readonly weeklyAwards: WeeklyAwardsDependencies;
}) {
  return new Hono()
    .use('/jobs/*', async (c, next) => {
      if (deps.jobsToken === undefined) throw new JobsOffError();
      if (!sameToken(bearerToken(c.req.header('authorization')), deps.jobsToken)) {
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

/** Compares in constant time, so a wrong token can't be guessed a byte at a time. */
function sameToken(given: string, expected: string): boolean {
  const [a, b] = [Buffer.from(given), Buffer.from(expected)];
  return a.length === b.length && timingSafeEqual(a, b);
}
