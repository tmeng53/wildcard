import type { z } from 'zod';

import type { MemberId, PromptMeme } from './domain/draft-request.js';

/**
 * A language model that answers in a set JSON shape, whoever provides it. Throws
 * `DisclaimerWriterUnavailableError` when it can't be reached, declines to answer, or answers
 * out of shape.
 */
export interface LanguageModel {
  answer<Reply>(request: {
    /** The standing instructions (a system prompt). */
    readonly instructions: string;
    /** What to answer. */
    readonly prompt: string;
    /** The shape of the answer. */
    readonly reply: z.ZodType<Reply>;
  }): Promise<Reply>;
}

/** This week's memes, from the meme library. */
export type MemesInUse = () => Promise<readonly PromptMeme[]>;

/** A request counted against a member's daily allowance, until it is given back. */
export type Reservation = string & z.BRAND<'Reservation'>;

/** Counts each member's requests for drafts, so nobody asks more than a day's worth. */
export interface DraftAllowance {
  /**
   * Counts one request by `member` at `at`, unless they already made `limit` after `since`.
   * Two requests at once can't both take the last one. Returns the reservation, or `undefined`
   * when the allowance is used up.
   */
  reserve(request: {
    readonly member: MemberId;
    readonly at: Date;
    readonly since: Date;
    readonly limit: number;
  }): Promise<Reservation | undefined>;
  /** Gives a reserved request back, for one that wrote nothing through no fault of the member. */
  release(reservation: Reservation): Promise<void>;
}

/**
 * Whether the member has consented to the current AI terms. Drafts need it: their reason goes
 * to the AI provider.
 */
export type AiConsentCheck = (member: MemberId) => Promise<boolean>;

/** The current time. */
export type Clock = () => Date;
