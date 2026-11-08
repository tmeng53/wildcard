import type { CoachWakes } from '@wildcard/coach';
import { Hono, type MiddlewareHandler } from 'hono';
import { z } from 'zod';

import { JobTokenInvalidError, JobsOffError, RouteNotFoundError } from '../errors.js';
import { deliver, ServerEvent, Subscriber, type EventHandlers } from '../events.js';
import { deliverCoachNotes, type CoachNotesDependencies } from '../flows/coach-notes.js';
import { fileWaitingFeedback, type FeedbackIssueDependencies } from '../flows/feedback-issues.js';
import { sendDailyProgress, type DailyProgressDependencies } from '../flows/daily-progress-push.js';
import { suggestSquadGoals, type SuggestGoal } from '../flows/squad-goal-suggestion.js';
import { giveWeeklyAwards, type WeeklyAwardsDependencies } from '../flows/weekly-awards.js';
import { logAlso, type Log } from '../log.js';
import type { IsScheduler } from '../ports.js';
import { bearerToken } from '../require-caller.js';

// Plain `z.object`: Pub/Sub's push carries more fields than we read.
// https://cloud.google.com/pubsub/docs/push#receive_push
const PubSubPush = z.object({
  message: z.object({ data: z.string().max(100_000), messageId: z.string() }),
  deliveryAttempt: z.number().optional(),
});

/** Lets only the scheduler's token through: Cloud Scheduler's or Pub/Sub's, or `JOBS_TOKEN`. */
function schedulerOnly(isScheduler: IsScheduler | undefined): MiddlewareHandler {
  return async (c, next) => {
    if (isScheduler === undefined) throw new JobsOffError();
    if (!(await isScheduler(bearerToken(c.req.header('authorization'))))) {
      throw new JobTokenInvalidError();
    }
    await next();
  };
}

/** The event a push carries, base64 JSON; undefined when it isn't JSON at all. */
function readEvent(data: string) {
  try {
    return ServerEvent.safeParse(JSON.parse(Buffer.from(data, 'base64').toString('utf8')));
  } catch {
    return undefined;
  }
}

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
    .use('/jobs/*', schedulerOnly(deps.isScheduler))
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

/**
 * `POST /jobs/events/{subscriber}`, where Pub/Sub pushes each event to each of its subscribers
 * (`events.ts`), signed for the scheduler's account. Not in openapi.json.
 */
export function eventPushes(deps: {
  readonly isScheduler: IsScheduler | undefined;
  /** What each subscriber does with the events Pub/Sub pushes. */
  readonly events: EventHandlers;
  readonly log: Log;
}) {
  return (
    new Hono()
      .use('/jobs/events/*', schedulerOnly(deps.isScheduler))
      // Pub/Sub retries anything but a 2xx, so a message that can't be read is answered 204: it
      // would never read better. A subscriber that fails answers 500, and Pub/Sub tries again.
      .post('/jobs/events/:subscriber', async (c) => {
        const subscriber = Subscriber.safeParse(c.req.param('subscriber'));
        if (!subscriber.success) throw new RouteNotFoundError(c.req.method, c.req.path);
        logAlso({ job: 'event', subscriber: subscriber.data });
        const push = PubSubPush.safeParse(await c.req.json().catch(() => undefined));
        const event = push.success ? readEvent(push.data.message.data) : undefined;
        if (!event?.success) {
          deps.log.error('event not readable', {
            messageId: push.success ? push.data.message.messageId : undefined,
          });
          return c.body(null, 204);
        }
        if (!(await deliver(deps.events, { subscriber: subscriber.data, event: event.data }))) {
          deps.log.error('event of another kind', { kind: event.data.kind });
        }
        return c.body(null, 204);
      })
  );
}
