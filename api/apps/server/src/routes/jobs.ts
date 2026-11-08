import type { CoachWakes } from '@wildcard/coach';
import { Hono } from 'hono';

import { JobTokenInvalidError, JobsOffError } from '../errors.js';
import { deliverCoachNotes, type CoachNotesDependencies } from '../flows/coach-notes.js';
import { fileWaitingFeedback, type FeedbackIssueDependencies } from '../flows/feedback-issues.js';
import { sendDailyProgress, type DailyProgressDependencies } from '../flows/daily-progress-push.js';
import { suggestSquadGoals, type SuggestGoal } from '../flows/squad-goal-suggestion.js';
import { giveWeeklyAwards, type WeeklyAwardsDependencies } from '../flows/weekly-awards.js';
import { logAlso } from '../log.js';
import type { IsScheduler } from '../ports.js';
import { bearerToken } from '../require-caller.js';

/**
 * Work a scheduler starts, not the app: `POST /jobs/daily-progress-push`, meant to run every 15
 * minutes or so, which also files the 意见反馈 messages still waiting for their issue, `POST /jobs/weekly-awards`, meant to run every hour, which also suggests captains
 * a higher squad goal (`flows/squad-goal-suggestion.ts`), and `POST /jobs/coach`,
 * meant to run every 10 minutes, which also delivers the coach's morning notes. Each call takes the
 * scheduler's bearer token: Cloud Scheduler's OIDC token on the hosted server, `JOBS_TOKEN`
 * on a local one. Not part of the app's contract, so not in openapi.json. Every entry a run logs
 * carries `job`, which the alerts `scripts/gcp-setup.sh` makes look for.
 */
export function jobs(deps: {
  readonly isScheduler: IsScheduler | undefined;
  readonly dailyProgress: DailyProgressDependencies;
  /** Files members' feedback that couldn't be filed as it was sent. */
  readonly feedbackIssues: FeedbackIssueDependencies;
  readonly weeklyAwards: WeeklyAwardsDependencies;
  /** Keeps a higher squad goal suggested to a captain with its notice, after the awards. */
  readonly suggestGoal: SuggestGoal;
  /** The AI coach's wakes; undefined without an OpenAI key, and then the coach never wakes. */
  readonly coach?: CoachWakes;
  /** Delivers the coach's morning notes once each member's morning comes, after the wakes run. */
  readonly coachNotes: CoachNotesDependencies;
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
      const feedback = await fileWaitingFeedback(deps.feedbackIssues);
      if (feedback.waiting > 0) deps.dailyProgress.log.warn('feedback still waiting', feedback);
      return c.json({ version: 1, ...run, feedback }, 200);
    })
    .post('/jobs/weekly-awards', async (c) => {
      logAlso({ job: 'weekly-awards' });
      const run = await giveWeeklyAwards(deps.weeklyAwards);
      deps.weeklyAwards.log.info('weekly awards run', { ...run });
      // Once the 战报 froze, captains of squads long over their goal hear of a higher one.
      const goals = await suggestSquadGoals({
        ...deps.weeklyAwards,
        suggestGoal: deps.suggestGoal,
      });
      deps.weeklyAwards.log.info('squad goal suggestions run', { ...goals });
      return c.json({ version: 1, ...run, goals }, 200);
    })
    .post('/jobs/coach', async (c) => {
      logAlso({ job: 'coach' });
      const run =
        deps.coach === undefined
          ? { coaching: false, squads: 0, queued: 0, done: 0, failed: 0 }
          : await deps.coach.run();
      // Notes the daily wake just wrote reach members already past their morning hour at once.
      const notes = await deliverCoachNotes(deps.coachNotes);
      // A failed wake keeps why on its row (get_squad_coaching shows it) and is tried again.
      if (run.failed > 0) deps.weeklyAwards.log.warn('some coach wakes failed', { ...run });
      else deps.weeklyAwards.log.info('coach run', { ...run });
      deps.weeklyAwards.log.info('coach notes run', { ...notes });
      return c.json({ version: 1, ...run, notes }, 200);
    });
}
