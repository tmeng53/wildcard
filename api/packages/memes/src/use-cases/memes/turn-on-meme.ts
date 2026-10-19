import type { MemePhrase } from '../../domain/meme.js';
import { MemeNotFoundError } from '../../errors.js';
import type { MemeStore } from '../../ports.js';

/**
 * Lets a turned-off meme be used again, e.g. one turned off by mistake. It is still used only
 * in the 4 weeks after its approval.
 */
export async function turnOnMeme(
  deps: { readonly store: MemeStore },
  phrase: MemePhrase,
): Promise<void> {
  if (!(await deps.store.turnOn(phrase))) throw new MemeNotFoundError(phrase);
}
