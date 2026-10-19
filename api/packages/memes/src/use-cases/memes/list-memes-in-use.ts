import { inUseSince, type MemeRecord } from '../../domain/meme.js';
import type { Clock, MemeStore } from '../../ports.js';

/** The memes the AI may use now: approved in the last 4 weeks and not turned off. */
export function listMemesInUse(deps: {
  readonly store: MemeStore;
  readonly clock: Clock;
}): Promise<MemeRecord[]> {
  return deps.store.listApprovedSince(inUseSince(deps.clock()));
}
