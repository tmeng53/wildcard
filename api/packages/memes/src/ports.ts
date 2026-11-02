import type { ApprovedMeme, LibraryMeme, MemePhrase, MemeRecord } from './domain/meme.js';

/** Where the meme library is kept. */
export interface MemeStore {
  /**
   * Saves memes approved at `approvedAt`, each with its expiry if it has one. A phrase already
   * in the library is left as it is; the database decides, so two saves at once can't add it
   * twice. Returns the phrases added.
   */
  add(memes: readonly ApprovedMeme[], approvedAt: Date): Promise<MemePhrase[]>;
  /**
   * Memes in use at `now`, newest first: approved by then, not expired by then and not turned
   * off.
   */
  listInUseAt(now: Date): Promise<MemeRecord[]>;
  /** Every meme in the library, expired and turned off included, newest first. */
  listAll(): Promise<LibraryMeme[]>;
  /** When a meme was approved, or undefined if the library hasn't got that phrase. */
  approvedAt(phrase: MemePhrase): Promise<Date | undefined>;
  /** Sets or clears when a meme expires. Says whether the library has that phrase. */
  setExpiry(phrase: MemePhrase, expiresAt: Date | null): Promise<boolean>;
  /** Turns a meme off at `at`. Says whether the library has that phrase. */
  turnOff(phrase: MemePhrase, at: Date): Promise<boolean>;
  /** Turns a meme back on. Says whether the library has that phrase. */
  turnOn(phrase: MemePhrase): Promise<boolean>;
}

/** The current time. */
export type Clock = () => Date;
