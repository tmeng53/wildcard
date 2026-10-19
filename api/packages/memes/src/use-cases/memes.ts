import type { MemePhrase, MemeRecord } from '../domain/meme.js';
import type { Clock, MemeStore } from '../ports.js';
import {
  addApprovedMemes,
  type AddApprovedMemesInput,
  type AddedMemes,
} from './memes/add-approved-memes.js';
import { listMemesInUse } from './memes/list-memes-in-use.js';
import { turnOffMeme } from './memes/turn-off-meme.js';

/** The meme library: adding approved memes, reading the ones in use, turning one off. */
export interface Memes {
  addApproved(input: AddApprovedMemesInput): Promise<AddedMemes>;
  listInUse(): Promise<MemeRecord[]>;
  turnOff(phrase: MemePhrase): Promise<void>;
}

export function createMemes(deps: { readonly store: MemeStore; readonly clock: Clock }): Memes {
  return {
    addApproved: (input) => addApprovedMemes(deps, input),
    listInUse: () => listMemesInUse(deps),
    turnOff: (phrase) => turnOffMeme(deps, phrase),
  };
}
