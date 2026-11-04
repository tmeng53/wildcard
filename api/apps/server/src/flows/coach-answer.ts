import { setTimeout as wait } from 'node:timers/promises';

import type { Log } from '../log.js';

/**
 * How long a request waits for the coach, inside the app's 15-second request timeout with the
 * pushes before it; slower work is the coach job's to finish.
 */
const COACH_WAIT_MS = 8_000;

/** Has the coach answer a member's reply to it now (the coach module's `answer`). */
export type CoachAnswerer = (input: {
  readonly checkIn: string;
  readonly comment: string;
  readonly coach: string;
}) => Promise<void>;

/** Has the coaches of the squads a check-in went to look at it now (the coach module's `checkedIn`). */
export type CoachLooker = (input: {
  readonly checkIn: string;
  readonly squads: readonly string[];
}) => Promise<void>;

/**
 * Runs the coach's work before a request ends, since Cloud Run gives the server CPU only while a
 * request runs. Never throws, and waits at most `COACH_WAIT_MS`: what the request saved stays
 * saved whether or not the coach has finished, and a wake still waiting or running is the coach
 * job's to finish (it runs every 10 minutes).
 */
async function coachWithinRequest({
  log,
  what,
  checkIn,
  work,
}: {
  readonly log: Log;
  readonly what: string;
  readonly checkIn: string;
  readonly work: () => Promise<void>;
}): Promise<void> {
  const stop = new AbortController();
  const late = wait(COACH_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(() => undefined);
  const working = work().catch((error: unknown) => {
    log.error(`coach ${what} failed`, { checkIn, error });
  });
  const outcome = await Promise.race([working, late]);
  stop.abort();
  if (outcome === 'late') log.warn(`coach ${what} still running`, { checkIn });
}

/** Has the coach answer a member's reply to it before the comment's request ends. */
export function answerCoachReply(
  deps: { readonly answer: CoachAnswerer; readonly log: Log },
  reply: Parameters<CoachAnswerer>[0],
): Promise<void> {
  return coachWithinRequest({
    log: deps.log,
    what: 'answer',
    checkIn: reply.checkIn,
    work: () => deps.answer(reply),
  });
}

/** Has the coaches look at a check-in just made before its request ends. */
export function coachLooksAtCheckIn(
  deps: { readonly look: CoachLooker; readonly log: Log },
  checkIn: Parameters<CoachLooker>[0],
): Promise<void> {
  return coachWithinRequest({
    log: deps.log,
    what: 'reply',
    checkIn: checkIn.checkIn,
    work: () => deps.look(checkIn),
  });
}
