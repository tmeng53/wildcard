import { setTimeout as wait } from 'node:timers/promises';

import type { Log } from '../log.js';

/** How long a comment's answer waits for the coach; a slower answer is the coach job's to finish. */
const ANSWER_WAIT_MS = 25_000;

/** Has the coach answer a member's reply to it now (the coach module's `answer`). */
export type CoachAnswerer = (input: {
  readonly checkIn: string;
  readonly comment: string;
  readonly coach: string;
}) => Promise<void>;

/**
 * Has the coach answer a member's reply to it before the comment's request ends, since Cloud Run
 * gives the server CPU only while a request runs. Never throws, and waits at most
 * `ANSWER_WAIT_MS`: the reply is saved whether or not the coach has answered, and a wake still
 * waiting or running is the coach job's to finish (it runs every 10 minutes).
 */
export async function answerCoachReply(
  deps: { readonly answer: CoachAnswerer; readonly log: Log },
  reply: Parameters<CoachAnswerer>[0],
): Promise<void> {
  const stop = new AbortController();
  const late = wait(ANSWER_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(
    () => undefined,
  );
  const answering = deps.answer(reply).catch((error: unknown) => {
    deps.log.error('coach answer failed', { checkIn: reply.checkIn, error });
  });
  const outcome = await Promise.race([answering, late]);
  stop.abort();
  if (outcome === 'late') deps.log.warn('coach answer still running', { checkIn: reply.checkIn });
}
