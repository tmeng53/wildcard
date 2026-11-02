import type { MemeRecord } from '../../domain/meme.js';
import type { Clock, MemeStore } from '../../ports.js';

/**
 * The memes the AI may use now: approved, not expired and not turned off. One dated ahead is
 * left out until its day comes.
 */
export function listMemesInUse(deps: {
  readonly store: MemeStore;
  readonly clock: Clock;
}): Promise<MemeRecord[]> {
  return deps.store.listInUseAt(deps.clock());
}
