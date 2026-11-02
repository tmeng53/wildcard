import type { MemePhrase, MemeRecord } from '../domain/meme.js';
import type { Clock, MemeStore } from '../ports.js';
import {
  addApprovedMemes,
  type AddApprovedMemesInput,
  type AddedMemes,
} from './memes/add-approved-memes.js';
import { listMemesInUse } from './memes/list-memes-in-use.js';
import { setMemeExpiry, type SetMemeExpiryInput } from './memes/set-meme-expiry.js';
import { turnOffMeme } from './memes/turn-off-meme.js';
import { turnOnMeme } from './memes/turn-on-meme.js';

/**
 * The meme library: adding approved memes, reading the ones in use, setting when one expires,
 * turning one off or back on.
 */
export interface Memes {
  addApproved(input: AddApprovedMemesInput): Promise<AddedMemes>;
  listInUse(): Promise<MemeRecord[]>;
  setExpiry(input: SetMemeExpiryInput): Promise<void>;
  turnOff(phrase: MemePhrase): Promise<void>;
  turnOn(phrase: MemePhrase): Promise<void>;
}

export function createMemes(deps: { readonly store: MemeStore; readonly clock: Clock }): Memes {
  return {
    addApproved: (input) => addApprovedMemes(deps, input),
    listInUse: () => listMemesInUse(deps),
    setExpiry: (input) => setMemeExpiry(deps, input),
    turnOff: (phrase) => turnOffMeme(deps, phrase),
    turnOn: (phrase) => turnOnMeme(deps, phrase),
  };
}
