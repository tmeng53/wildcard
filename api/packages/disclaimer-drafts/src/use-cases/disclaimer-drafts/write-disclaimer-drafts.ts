import type { DisclaimerStyle } from '@wildcard/disclaimer-styles';
import { mentionsSelfHarm } from '@wildcard/typed-text';

import type { DraftReason, MemberId, PromptMeme } from '../../domain/draft-request.js';
import { ModelReply, outcomeOf, type DraftsOutcome } from '../../domain/drafts.js';
import { INSTRUCTIONS, promptFor } from '../../domain/prompt.js';
import {
  AiConsentRequiredError,
  DisclaimerDraftsUsedUpError,
  DisclaimerWriterUnavailableError,
} from '../../errors.js';
import type {
  AiConsentCheck,
  Clock,
  DraftAllowance,
  LanguageModel,
  MemesInUse,
  Random,
} from '../../ports.js';

/** Batches a member may ask for in a day: the first and 5 换一批 (spec A4). */
export const BATCHES_PER_DAY = 6;
/** A day, for the allowance: the last 24 hours, so it needs no time zone. */
const DAY_MS = 86_400_000;
/** How often a request gets one of this week's memes (Tracy, 2026-10-19). */
export const MEME_CHANCE = 0.3;

export interface WriteDisclaimerDraftsInput {
  readonly member: MemberId;
  readonly reason: DraftReason;
  readonly style: DisclaimerStyle;
}

/**
 * Three drafts for a member's 请假条, written by the model from their reason, or the care
 * line, or a decline. Only asked for when the member taps the button, never as they type, and
 * only for a member with a current AI consent: the care line needs none, since no AI sees it.
 */
export async function writeDisclaimerDrafts(
  deps: {
    readonly model: LanguageModel;
    readonly memes: MemesInUse;
    readonly allowance: DraftAllowance;
    readonly aiConsent: AiConsentCheck;
    readonly clock: Clock;
    readonly random: Random;
  },
  input: WriteDisclaimerDraftsInput,
): Promise<DraftsOutcome> {
  if (mentionsSelfHarm(input.reason)) return { kind: 'care' };
  if (!(await deps.aiConsent(input.member))) throw new AiConsentRequiredError();

  const now = deps.clock();
  const reservation = await deps.allowance.reserve({
    member: input.member,
    at: now,
    since: new Date(now.getTime() - DAY_MS),
    limit: BATCHES_PER_DAY,
  });
  if (reservation === undefined) throw new DisclaimerDraftsUsedUpError();

  try {
    const meme = await memeFor(deps, input.style);
    const reply = await deps.model.answer({
      instructions: INSTRUCTIONS,
      prompt: promptFor({ reason: input.reason, style: input.style, meme }),
      reply: ModelReply,
    });
    const outcome = outcomeOf(reply);
    if (outcome === undefined) {
      throw new DisclaimerWriterUnavailableError({
        cause: new Error('The drafts failed the checks'),
      });
    }
    return outcome;
  } catch (error) {
    // Nothing was shown, so the request doesn't count.
    await deps.allowance.release(reservation);
    throw error;
  }
}

/**
 * One of this week's memes that suits the style, on MEME_CHANCE of requests, or none. Never the
 * whole library: one meme at a time keeps memes in moderation and the prompt short.
 */
async function memeFor(
  deps: { readonly memes: MemesInUse; readonly random: Random },
  style: DisclaimerStyle,
): Promise<PromptMeme | undefined> {
  if (deps.random() >= MEME_CHANCE) return undefined;
  const suited = (await deps.memes()).filter((meme) => meme.styles.includes(style));
  return suited[Math.floor(deps.random() * suited.length)];
}
