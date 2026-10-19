import type { MemePhrase } from '../../domain/meme.js';
import { MemeNotFoundError } from '../../errors.js';
import type { Clock, MemeStore } from '../../ports.js';

/** Stops a meme from being used again, e.g. one that turned out to be in poor taste. */
export async function turnOffMeme(
  deps: { readonly store: MemeStore; readonly clock: Clock },
  phrase: MemePhrase,
): Promise<void> {
  if (!(await deps.store.turnOff(phrase, deps.clock()))) throw new MemeNotFoundError(phrase);
}
