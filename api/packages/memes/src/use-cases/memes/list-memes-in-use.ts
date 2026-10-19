import { inUseSince, type MemeRecord } from '../../domain/meme.js';
import type { Clock, MemeStore } from '../../ports.js';

/**
 * The memes the AI may use now: approved in the last 4 weeks and not turned off. One dated
 * ahead is left out until its day comes.
 */
export function listMemesInUse(deps: {
  readonly store: MemeStore;
  readonly clock: Clock;
}): Promise<MemeRecord[]> {
  const now = deps.clock();
  return deps.store.listApprovedBetween({ from: inUseSince(now), to: now });
}
