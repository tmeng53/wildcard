import type { MemberId, PromptMeme } from './domain/draft-request.js';
import type { DiceLines } from './domain/dice.js';
import type { DraftSettings } from './domain/settings.js';

/** Where the dice lines are kept: one value, and a log of every change. */
export interface DiceLinesStore {
  /**
   * The lines now. `forUpdate` holds the row until the caller's transaction ends, so two admins
   * changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<DiceLines>;
  /**
   * Saves `dice` with `by` as who changed them, unless they are the lines already: then nothing
   * is saved or logged. Says whether anything changed.
   */
  save(dice: DiceLines, by: MemberId): Promise<boolean>;
}

/** Where the draft settings are kept: one value, and a log of every change to it. */
export interface DraftSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<DraftSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: DraftSettings, by: MemberId): Promise<boolean>;
}

/** This week's memes, from the meme library. */
export type MemesInUse = () => Promise<readonly PromptMeme[]>;

/**
 * Whether the member has consented to the current AI terms. Drafts need it: their reason goes
 * to the AI provider.
 */
export type AiConsentCheck = (member: MemberId) => Promise<boolean>;

/** A random number from 0 up to, not including, 1. */
export type Random = () => number;
