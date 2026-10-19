import type { MemeDraft, MemePhrase, MemeRecord } from './domain/meme.js';

/** Where the meme library is kept. */
export interface MemeStore {
  /**
   * Saves memes approved at `approvedAt`. A phrase already in the library is left as it is;
   * the database decides, so two saves at once can't add it twice. Returns the phrases added.
   */
  add(memes: readonly MemeDraft[], approvedAt: Date): Promise<MemePhrase[]>;
  /** Memes approved from `from` to `to` (both included) and not turned off, newest first. */
  listApprovedBetween(range: { readonly from: Date; readonly to: Date }): Promise<MemeRecord[]>;
  /** Turns a meme off at `at`. Says whether the library has that phrase. */
  turnOff(phrase: MemePhrase, at: Date): Promise<boolean>;
}

/** The current time. */
export type Clock = () => Date;
